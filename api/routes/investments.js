// Investimentos: carteira, movimentos, rentabilidade e performance (spec §17).
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const scope = require('../lib/scope');
const ledger = require('../lib/ledger');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

const TYPE_LABELS = {
  treasury: 'Tesouro Direto',
  cdb: 'CDB',
  lci_lca: 'LCI/LCA',
  stock: 'Ações',
  etf: 'ETF',
  reit: 'Fundos Imobiliários',
  crypto: 'Criptomoedas',
  fund: 'Fundos',
  fixed_income: 'Renda fixa',
  savings: 'Poupança',
  pension: 'Previdência',
  other: 'Outros',
};

const TYPES = Object.keys(TYPE_LABELS);
const KINDS = ['contribution', 'withdrawal', 'dividend', 'yield', 'fee', 'tax', 'valuation'];

const KIND_LABELS = {
  contribution: 'Aporte',
  withdrawal: 'Resgate',
  dividend: 'Dividendo',
  yield: 'Rendimento',
  fee: 'Taxa',
  tax: 'Imposto',
  valuation: 'Marcação a mercado',
};

function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 });
}

function notFound(message) {
  return Object.assign(new Error(message), { status: 404 });
}

function parseBool(value) {
  if (value === undefined || value === null || value === '') return undefined;
  return value === true || value === 'true' || value === 1 || value === '1';
}

function round(value, decimals = 2) {
  const factor = 10 ** decimals;
  return Math.round((Number(value) + Number.EPSILON) * factor) / factor;
}

function positiveAmount(value, label = 'Valor') {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) throw badRequest(`${label} deve ser maior que zero.`);
  return amount;
}

// Data de referência do investimento: purchase_date quando informada, senão a criação.
function startDateOf(investment) {
  return investment.purchase_date || String(investment.created_at || '').slice(0, 10) || dates.toIsoDate(new Date());
}

// Métricas derivadas — calculadas em JS porque dependem de datas e potências.
function decorate(investment) {
  const invested = Number(investment.invested_amount || 0);
  const current = Number(investment.current_amount || 0);
  const profit = round(current - invested);
  const start = startDateOf(investment);
  const daysHeld = Math.max(dates.daysBetween(start, dates.toIsoDate(new Date())), 0);

  // Rentabilidade anualizada composta: ((atual/investido)^(365/dias) - 1) * 100.
  // Só faz sentido com histórico mínimo — abaixo de 30 dias o número explode.
  let annualized = null;
  if (daysHeld >= 30 && invested > 0 && current > 0) {
    annualized = round((Math.pow(current / invested, 365 / daysHeld) - 1) * 100, 2);
  }

  return {
    ...investment,
    type_label: TYPE_LABELS[investment.type] || investment.type,
    invested_amount: invested,
    current_amount: current,
    profit,
    profit_percent: invested > 0 ? round((profit / invested) * 100) : 0,
    dividends_total: round(Number(investment.dividends_total || 0)),
    contributions_total: round(Number(investment.contributions_total || 0)),
    withdrawals_total: round(Number(investment.withdrawals_total || 0)),
    days_held: daysHeld,
    annualized_return: annualized,
  };
}

const TOTALS_SELECT = `
  COALESCE((SELECT SUM(m.amount) FROM investment_movements m
            WHERE m.investment_id = i.id AND m.kind IN ('dividend','yield')), 0) AS dividends_total,
  COALESCE((SELECT SUM(m.amount) FROM investment_movements m
            WHERE m.investment_id = i.id AND m.kind = 'contribution'), 0) AS contributions_total,
  COALESCE((SELECT SUM(m.amount) FROM investment_movements m
            WHERE m.investment_id = i.id AND m.kind = 'withdrawal'), 0) AS withdrawals_total`;

async function loadVisible(userId, id) {
  const visibility = await scope.visibilityClause(userId, 'i');
  const [rows] = await db.query(
    `SELECT i.*, a.name AS account_name, f.name AS family_name, (i.user_id = ?) AS is_own, ${TOTALS_SELECT}
     FROM investments i
     LEFT JOIN accounts a ON a.id = i.account_id
     LEFT JOIN families f ON f.id = i.family_id
     WHERE i.id = ? AND ${visibility.sql}`,
    [userId, id, ...visibility.params]
  );
  if (rows.length === 0) throw notFound('Investimento não encontrado.');
  return rows[0];
}

async function loadOwn(userId, id, conn = db) {
  const [rows] = await conn.query('SELECT * FROM investments WHERE id = ? AND user_id = ?', [id, userId]);
  if (rows.length === 0) throw notFound('Investimento não encontrado.');
  return rows[0];
}

/**
 * Recalcula invested_amount/current_amount reproduzindo os movimentos em ordem.
 * Reprocessar é mais seguro que somar/subtrair incrementalmente: garante que a
 * exclusão de um movimento (inclusive de uma marcação a mercado, que sobrescreve
 * o valor atual) deixe os totais coerentes com o histórico restante.
 */
async function recomputeTotals(conn, investmentId) {
  const [movements] = await conn.query(
    'SELECT kind, amount FROM investment_movements WHERE investment_id = ? ORDER BY date ASC, id ASC',
    [investmentId]
  );

  let invested = 0;
  let current = 0;
  for (const m of movements) {
    const amount = Number(m.amount || 0);
    if (m.kind === 'contribution') { invested += amount; current += amount; }
    else if (m.kind === 'withdrawal') { invested -= amount; current -= amount; }
    else if (m.kind === 'dividend' || m.kind === 'yield') current += amount;
    else if (m.kind === 'fee' || m.kind === 'tax') current -= amount;
    else if (m.kind === 'valuation') current = amount;
  }

  invested = round(Math.max(invested, 0));
  current = round(Math.max(current, 0));

  await conn.query('UPDATE investments SET invested_amount = ?, current_amount = ? WHERE id = ?', [invested, current, investmentId]);
  return { invested_amount: invested, current_amount: current };
}

// GET / — carteira do usuário + investimentos das famílias visíveis.
router.get('/', asyncHandler(async (req, res) => {
  const visibility = await scope.visibilityClause(req.userId, 'i');
  const params = [req.userId, ...visibility.params];
  let sql = `SELECT i.*, a.name AS account_name, f.name AS family_name, (i.user_id = ?) AS is_own, ${TOTALS_SELECT}
             FROM investments i
             LEFT JOIN accounts a ON a.id = i.account_id
             LEFT JOIN families f ON f.id = i.family_id
             WHERE ${visibility.sql}`;

  if (req.query.type) {
    if (!TYPES.includes(req.query.type)) throw badRequest(`Tipo inválido. Use: ${TYPES.join(', ')}.`);
    sql += ' AND i.type = ?';
    params.push(req.query.type);
  }
  const active = parseBool(req.query.active);
  if (active !== undefined) {
    sql += ' AND i.active = ?';
    params.push(active ? 1 : 0);
  }
  sql += ' ORDER BY i.current_amount DESC, i.name';

  const [rows] = await db.query(sql, params);
  res.json(rows.map(decorate));
}));

// GET /summary — consolidado da carteira.
router.get('/summary', asyncHandler(async (req, res) => {
  const visibility = await scope.visibilityClause(req.userId, 'i');
  const [rows] = await db.query(
    `SELECT i.*, (i.user_id = ?) AS is_own, ${TOTALS_SELECT}
     FROM investments i
     WHERE i.active = TRUE AND ${visibility.sql}`,
    [req.userId, ...visibility.params]
  );

  const items = rows.map(decorate);
  const invested = round(items.reduce((sum, i) => sum + i.invested_amount, 0));
  const current = round(items.reduce((sum, i) => sum + i.current_amount, 0));
  const profit = round(current - invested);

  const year = dates.toIsoDate(new Date()).slice(0, 4);
  const [[dividends]] = await db.query(
    `SELECT COALESCE(SUM(m.amount), 0) AS total
     FROM investment_movements m
     JOIN investments i ON i.id = m.investment_id
     WHERE m.kind IN ('dividend','yield') AND YEAR(m.date) = ? AND ${visibility.sql}`,
    [year, ...visibility.params]
  );

  const byType = new Map();
  for (const item of items) {
    const entry = byType.get(item.type) || { type: item.type, label: TYPE_LABELS[item.type] || item.type, total: 0, count: 0 };
    entry.total = round(entry.total + item.current_amount);
    entry.count += 1;
    byType.set(item.type, entry);
  }
  const distribution = [...byType.values()]
    .map(entry => ({ ...entry, percent: current > 0 ? round((entry.total / current) * 100) : 0 }))
    .sort((a, b) => b.total - a.total);

  // Ranking pela rentabilidade percentual; só entram os que têm valor investido.
  const ranked = items
    .filter(i => i.invested_amount > 0)
    .map(i => ({
      id: i.id, name: i.name, type: i.type, type_label: i.type_label,
      invested_amount: i.invested_amount, current_amount: i.current_amount,
      profit: i.profit, profit_percent: i.profit_percent, annualized_return: i.annualized_return,
    }))
    .sort((a, b) => b.profit_percent - a.profit_percent);

  res.json({
    count: items.length,
    invested_total: invested,
    current_total: current,
    profit,
    profit_percent: invested > 0 ? round((profit / invested) * 100) : 0,
    dividends_year: round(Number(dividends.total || 0)),
    dividends_year_reference: year,
    distribution,
    best_performers: ranked.slice(0, 5),
    worst_performers: ranked.slice(-5).reverse(),
  });
}));

// GET /performance — evolução mensal da carteira (investido vs valor atual).
router.get('/performance', asyncHandler(async (req, res) => {
  const months = Math.min(Math.max(parseInt(req.query.months, 10) || 12, 1), 120);
  const visibility = await scope.visibilityClause(req.userId, 'i');

  const [investments] = await db.query(
    `SELECT i.id, i.name, i.purchase_date, i.created_at FROM investments i WHERE ${visibility.sql}`,
    visibility.params
  );

  const ids = investments.map(i => i.id);
  let movements = [];
  if (ids.length > 0) {
    const [rows] = await db.query(
      `SELECT investment_id, kind, amount, date FROM investment_movements
       WHERE investment_id IN (${ids.map(() => '?').join(', ')})
       ORDER BY date ASC, id ASC`,
      ids
    );
    movements = rows;
  }

  const currentMonth = dates.currentMonth();
  const series = [];

  for (let offset = months - 1; offset >= 0; offset--) {
    const month = dates.addMonthsToMonth(currentMonth, -offset);
    const { end } = dates.monthRange(month);
    let invested = 0;
    let current = 0;

    // Reproduz os movimentos até o fim do mês para reconstruir a posição.
    for (const id of ids) {
      let inv = 0;
      let cur = 0;
      for (const m of movements) {
        if (m.investment_id !== id) continue;
        if (String(m.date).slice(0, 10) > end) continue;
        const amount = Number(m.amount || 0);
        if (m.kind === 'contribution') { inv += amount; cur += amount; }
        else if (m.kind === 'withdrawal') { inv -= amount; cur -= amount; }
        else if (m.kind === 'dividend' || m.kind === 'yield') cur += amount;
        else if (m.kind === 'fee' || m.kind === 'tax') cur -= amount;
        else if (m.kind === 'valuation') cur = amount;
      }
      invested += Math.max(inv, 0);
      current += Math.max(cur, 0);
    }

    series.push({
      month,
      invested_total: round(invested),
      current_total: round(current),
      profit: round(current - invested),
      accumulated_return_percent: invested > 0 ? round(((current - invested) / invested) * 100) : 0,
    });
  }

  res.json({ months, series });
}));

// GET /:id — detalhe, movimentos e evolução mensal do valor.
router.get('/:id', asyncHandler(async (req, res) => {
  const investment = await loadVisible(req.userId, req.params.id);

  const [movements] = await db.query(
    `SELECT m.*, t.description AS transaction_description
     FROM investment_movements m
     LEFT JOIN transactions t ON t.id = m.transaction_id AND t.deleted_at IS NULL
     WHERE m.investment_id = ?
     ORDER BY m.date ASC, m.id ASC`,
    [investment.id]
  );

  // Evolução: cada marcação a mercado fecha o mês; o mês corrente usa o valor atual.
  const byMonth = new Map();
  for (const m of movements.filter(m => m.kind === 'valuation')) {
    byMonth.set(String(m.date).slice(0, 7), round(Number(m.amount || 0)));
  }
  byMonth.set(dates.currentMonth(), round(Number(investment.current_amount || 0)));
  const evolution = [...byMonth.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : 1))
    .map(([month, value]) => ({ month, current_amount: value }));

  res.json({
    ...decorate(investment),
    movements: movements.map(m => ({
      ...m,
      kind_label: KIND_LABELS[m.kind] || m.kind,
      amount: Number(m.amount || 0),
    })),
    evolution,
  });
}));

// POST / — cria o investimento já com o aporte inicial registrado.
router.post('/', asyncHandler(async (req, res) => {
  const {
    name, type, broker, ticker, invested_amount, current_amount, quantity, currency,
    purchase_date, maturity_date, notes, account_id, family_id, debit_account,
  } = req.body;

  if (!name || !String(name).trim()) throw badRequest('Nome do investimento é obrigatório.');
  if (!type || !TYPES.includes(type)) throw badRequest(`Tipo inválido. Use: ${TYPES.join(', ')}.`);
  const invested = positiveAmount(invested_amount, 'Valor investido');
  const current = current_amount === undefined || current_amount === null ? invested : Number(current_amount);
  if (!Number.isFinite(current) || current < 0) throw badRequest('Valor atual inválido.');

  if (family_id) await scope.assertCanUseFamily(req.userId, family_id);

  let account = null;
  if (account_id) {
    const [rows] = await db.query('SELECT * FROM accounts WHERE id = ? AND user_id = ?', [account_id, req.userId]);
    if (rows.length === 0) throw notFound('Conta não encontrada.');
    account = rows[0];
  }

  const purchase = purchase_date || dates.toIsoDate(new Date());

  const created = await withTransaction(async conn => {
    const [result] = await conn.query(
      `INSERT INTO investments
         (user_id, family_id, account_id, name, type, broker, ticker, invested_amount, current_amount,
          quantity, currency, purchase_date, maturity_date, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        req.userId, family_id || null, account_id || null, String(name).trim(), type,
        broker || null, ticker || null, invested, current,
        quantity === undefined || quantity === null ? null : Number(quantity),
        currency || account?.currency || req.user.currency || 'BRL',
        purchase, maturity_date || null, notes || null,
      ]
    );
    const investmentId = result.insertId;

    let transactionId = null;
    // Aporte sai da conta somente quando o usuário pede explicitamente.
    if (account && debit_account === true) {
      const transaction = await ledger.createTransaction(conn, req.userId, {
        account_id: account.id,
        type: 'expense',
        amount: invested,
        date: purchase,
        description: `Aporte: ${String(name).trim()}`,
        currency: account.currency,
        family_id: family_id || null,
        investment_id: investmentId,
        source: 'manual',
      });
      transactionId = transaction.id;
    }

    await conn.query(
      `INSERT INTO investment_movements (investment_id, kind, amount, quantity, date, transaction_id, notes)
       VALUES (?, 'contribution', ?, ?, ?, ?, ?)`,
      [investmentId, invested, quantity === undefined || quantity === null ? null : Number(quantity), purchase, transactionId, 'Aporte inicial']
    );

    // Valor atual diferente do investido nasce como marcação a mercado, para o
    // histórico continuar reproduzindo exatamente os totais gravados.
    if (round(current) !== round(invested)) {
      await conn.query(
        `INSERT INTO investment_movements (investment_id, kind, amount, date, notes)
         VALUES (?, 'valuation', ?, ?, ?)`,
        [investmentId, current, purchase, 'Valor de mercado inicial']
      );
    }

    const [rows] = await conn.query('SELECT * FROM investments WHERE id = ?', [investmentId]);
    return rows[0];
  });

  await audit(req.userId, 'investment', created.id, 'create', created);
  res.status(201).json(created);
}));

// PUT /:id — dados cadastrais; current_amount explícito gera marcação a mercado.
router.put('/:id', asyncHandler(async (req, res) => {
  const before = await loadOwn(req.userId, req.params.id);
  const {
    name, type, broker, ticker, quantity, currency, purchase_date, maturity_date,
    notes, account_id, family_id, active, current_amount,
  } = req.body;

  if (type !== undefined && !TYPES.includes(type)) throw badRequest(`Tipo inválido. Use: ${TYPES.join(', ')}.`);
  if (family_id) await scope.assertCanUseFamily(req.userId, family_id);
  if (account_id) {
    const [rows] = await db.query('SELECT id FROM accounts WHERE id = ? AND user_id = ?', [account_id, req.userId]);
    if (rows.length === 0) throw notFound('Conta não encontrada.');
  }

  let valuation = null;
  if (current_amount !== undefined && current_amount !== null) {
    const value = Number(current_amount);
    if (!Number.isFinite(value) || value < 0) throw badRequest('Valor atual inválido.');
    if (round(value) !== round(Number(before.current_amount || 0))) valuation = value;
  }

  const updated = await withTransaction(async conn => {
    await conn.query(
      `UPDATE investments SET
         name = ?, type = ?, broker = ?, ticker = ?, quantity = ?, currency = ?,
         purchase_date = ?, maturity_date = ?, notes = ?, account_id = ?, family_id = ?, active = ?
       WHERE id = ? AND user_id = ?`,
      [
        name === undefined ? before.name : String(name).trim(),
        type === undefined ? before.type : type,
        broker === undefined ? before.broker : (broker || null),
        ticker === undefined ? before.ticker : (ticker || null),
        quantity === undefined ? before.quantity : (quantity === null ? null : Number(quantity)),
        currency === undefined ? before.currency : currency,
        purchase_date === undefined ? before.purchase_date : (purchase_date || null),
        maturity_date === undefined ? before.maturity_date : (maturity_date || null),
        notes === undefined ? before.notes : (notes || null),
        account_id === undefined ? before.account_id : (account_id || null),
        family_id === undefined ? before.family_id : (family_id || null),
        active === undefined ? before.active : (parseBool(active) ? 1 : 0),
        before.id, req.userId,
      ]
    );

    if (valuation !== null) {
      const previous = round(Number(before.current_amount || 0));
      // O movimento guarda o novo valor de mercado (semântica de 'valuation');
      // a diferença fica na observação para leitura humana e auditoria.
      await conn.query(
        `INSERT INTO investment_movements (investment_id, kind, amount, date, notes)
         VALUES (?, 'valuation', ?, ?, ?)`,
        [
          before.id, valuation, dates.toIsoDate(new Date()),
          `Ajuste de ${previous.toFixed(2)} para ${round(valuation).toFixed(2)} (diferença ${round(valuation - previous).toFixed(2)})`,
        ]
      );
      await conn.query('UPDATE investments SET current_amount = ? WHERE id = ?', [round(valuation), before.id]);
    }

    const [rows] = await conn.query('SELECT * FROM investments WHERE id = ?', [before.id]);
    return rows[0];
  });

  await audit(req.userId, 'investment', before.id, 'update', { before, after: updated });
  res.json(updated);
}));

// DELETE /:id — remove o investimento e solta as transações vinculadas.
router.delete('/:id', asyncHandler(async (req, res) => {
  const investment = await loadOwn(req.userId, req.params.id);

  await withTransaction(async conn => {
    // Histórico financeiro é preservado: só perde o vínculo com o investimento.
    await conn.query('UPDATE transactions SET investment_id = NULL WHERE investment_id = ?', [investment.id]);
    await conn.query('DELETE FROM investments WHERE id = ? AND user_id = ?', [investment.id, req.userId]);
  });

  await audit(req.userId, 'investment', investment.id, 'delete', investment);
  res.json({ message: 'Investimento excluído.' });
}));

// POST /:id/movements — aporte, resgate, provento, taxa ou marcação a mercado.
router.post('/:id/movements', asyncHandler(async (req, res) => {
  const investment = await loadOwn(req.userId, req.params.id);
  const { kind, amount, quantity, unit_price, date, notes, account_id } = req.body;

  if (!kind || !KINDS.includes(kind)) throw badRequest(`Tipo de movimento inválido. Use: ${KINDS.join(', ')}.`);
  const value = kind === 'valuation' ? Number(amount) : positiveAmount(amount, 'Valor do movimento');
  if (kind === 'valuation' && (!Number.isFinite(value) || value < 0)) throw badRequest('Valor de mercado inválido.');
  const movementDate = date || dates.toIsoDate(new Date());

  let account = null;
  if (account_id) {
    const [rows] = await db.query('SELECT * FROM accounts WHERE id = ? AND user_id = ?', [account_id, req.userId]);
    if (rows.length === 0) throw notFound('Conta não encontrada.');
    account = rows[0];
  }

  if (kind === 'withdrawal') {
    const invested = Number(investment.invested_amount || 0);
    const current = Number(investment.current_amount || 0);
    if (value > current + 0.005) throw badRequest(`Resgate de ${value.toFixed(2)} maior que o valor atual de ${current.toFixed(2)}.`);
    if (value > invested + 0.005) throw badRequest(`Resgate de ${value.toFixed(2)} maior que o valor investido de ${invested.toFixed(2)}.`);
  }
  if ((kind === 'fee' || kind === 'tax') && value > Number(investment.current_amount || 0) + 0.005) {
    throw badRequest('O valor lançado deixaria o investimento negativo.');
  }

  const result = await withTransaction(async conn => {
    let transactionId = null;

    // Aportes/resgates movem dinheiro da conta; proventos entram como receita.
    if (account) {
      const flow = {
        contribution: { type: 'expense', description: `Aporte: ${investment.name}` },
        withdrawal: { type: 'income', description: `Resgate: ${investment.name}` },
        dividend: { type: 'income', description: `Dividendo: ${investment.name}` },
        yield: { type: 'income', description: `Rendimento: ${investment.name}` },
      }[kind];

      if (flow) {
        const transaction = await ledger.createTransaction(conn, req.userId, {
          account_id: account.id,
          type: flow.type,
          amount: value,
          date: movementDate,
          description: flow.description,
          notes: notes || null,
          currency: account.currency,
          family_id: investment.family_id || null,
          investment_id: investment.id,
          source: 'manual',
        });
        transactionId = transaction.id;
      }
    }

    const [inserted] = await conn.query(
      `INSERT INTO investment_movements
         (investment_id, kind, amount, quantity, unit_price, date, transaction_id, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        investment.id, kind, value,
        quantity === undefined || quantity === null ? null : Number(quantity),
        unit_price === undefined || unit_price === null ? null : Number(unit_price),
        movementDate, transactionId, notes || null,
      ]
    );

    const totals = await recomputeTotals(conn, investment.id);
    const [rows] = await conn.query('SELECT * FROM investment_movements WHERE id = ?', [inserted.insertId]);
    return { movement: rows[0], totals };
  });

  await audit(req.userId, 'investment', investment.id, 'update', { movement: result.movement });
  res.status(201).json({
    ...result.movement,
    kind_label: KIND_LABELS[result.movement.kind] || result.movement.kind,
    investment: result.totals,
  });
}));

// DELETE /:id/movements/:movementId — reverte o movimento e os totais.
router.delete('/:id/movements/:movementId', asyncHandler(async (req, res) => {
  const investment = await loadOwn(req.userId, req.params.id);

  const totals = await withTransaction(async conn => {
    const [rows] = await conn.query(
      'SELECT * FROM investment_movements WHERE id = ? AND investment_id = ?',
      [req.params.movementId, investment.id]
    );
    if (rows.length === 0) throw notFound('Movimento não encontrado.');
    const movement = rows[0];

    await conn.query('DELETE FROM investment_movements WHERE id = ?', [movement.id]);
    if (movement.transaction_id) {
      const [tx] = await conn.query(
        'SELECT id FROM transactions WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
        [movement.transaction_id, req.userId]
      );
      if (tx.length > 0) await ledger.deleteTransaction(conn, req.userId, movement.transaction_id);
    }

    return recomputeTotals(conn, investment.id);
  });

  await audit(req.userId, 'investment', investment.id, 'update', { deleted_movement: req.params.movementId });
  res.json({ message: 'Movimento removido.', investment: totals });
}));

module.exports = router;
