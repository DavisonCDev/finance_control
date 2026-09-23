// Orçamento por categoria com alertas, cópia entre meses e histórico (spec §9).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const { notify } = require('../lib/notify');
const dates = require('../lib/dates');
const scope = require('../lib/scope');

const router = express.Router();
router.use(authenticate);

function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 });
}

function parseBool(value) {
  if (value === undefined || value === null || value === '') return undefined;
  return value === true || value === 'true' || value === 1 || value === '1';
}

function assertMonth(month, field = 'month') {
  if (!/^\d{4}-\d{2}$/.test(String(month))) throw badRequest(`Informe ${field} no formato AAAA-MM.`);
  return String(month);
}

/**
 * Intervalo do mês do usuário. Quando first_day_of_month > 1 o ciclo financeiro
 * não coincide com o mês civil: começa nesse dia e termina no dia anterior do
 * mês seguinte (ex.: dia 5 → 05/03 a 04/04 para o mês 2024-03).
 */
function monthBounds(month, firstDay = 1) {
  const day = Number(firstDay) || 1;
  if (day <= 1) return dates.monthRange(month);

  const [year, m] = month.split('-').map(Number);
  const start = new Date(year, m - 1, dates.clampDay(year, m - 1, day));
  const nextStart = new Date(year, m, dates.clampDay(year, m, day));
  return { start: dates.toIsoDate(start), end: dates.toIsoDate(dates.addDays(nextStart, -1)) };
}

// Dias que ainda faltam no ciclo (inclusive hoje). Mês futuro conta integral.
function daysLeftIn({ start, end }) {
  const today = dates.toIsoDate(new Date());
  if (today < start) return dates.daysBetween(start, end) + 1;
  if (today > end) return 0;
  return dates.daysBetween(today, end) + 1;
}

// Mapa categoria-pai → [ids das filhas], para somar subcategorias no orçamento.
async function childrenOf(categoryIds) {
  const map = new Map();
  if (categoryIds.length === 0) return map;
  const placeholders = categoryIds.map(() => '?').join(', ');
  const [rows] = await db.query(
    `SELECT id, parent_id FROM categories WHERE parent_id IN (${placeholders})`,
    categoryIds
  );
  for (const row of rows) {
    const key = Number(row.parent_id);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(Number(row.id));
  }
  return map;
}

// Total gasto por categoria no intervalo. So conta despesa efetivamente paga:
// compra no cartao nao e gasto aqui — ela vira gasto quando a fatura e paga,
// e pagamento de fatura e contabilizado na secao de cartao, nao na categoria.
async function spentByCategory(userId, { start, end }) {
  const visibility = await scope.visibilityClause(userId, 't');
  const [rows] = await db.query(
    `SELECT t.category_id, COALESCE(SUM(t.amount), 0) AS spent
     FROM transactions t
     WHERE ${visibility.sql}
       AND t.type = 'expense' AND t.deleted_at IS NULL
       AND t.status <> 'cancelled'
       AND t.is_paid = TRUE
       AND t.card_id IS NULL
       AND (t.source IS NULL OR t.source <> 'invoice_payment')
       AND t.date BETWEEN ? AND ?
     GROUP BY t.category_id`,
    [...visibility.params, start, end]
  );

  const map = new Map();
  for (const row of rows) map.set(Number(row.category_id), Number(row.spent));
  return map;
}

function statusFor(percent, threshold) {
  if (percent >= 100) return 'over';
  if (percent >= Number(threshold || 80)) return 'near';
  return 'ok';
}

// Monta a linha de resposta de um orçamento com gasto, percentual e status.
function decorate(budget, spent, daysLeft) {
  const budgeted = Number(budget.amount);
  const remaining = budgeted - spent;
  // Percentual real (pode passar de 100) para o app mostrar o estouro.
  const percent = budgeted > 0 ? (spent / budgeted) * 100 : (spent > 0 ? 100 : 0);

  return {
    id: budget.id,
    user_id: budget.user_id,
    category_id: budget.category_id,
    budget_month: budget.budget_month,
    amount: budgeted,
    alert_threshold: Number(budget.alert_threshold || 80),
    rollover: !!budget.rollover,
    family_id: budget.family_id,
    notified_near_at: budget.notified_near_at,
    notified_over_at: budget.notified_over_at,
    category_name: budget.category_name,
    category_color: budget.category_color,
    category_icon: budget.category_icon,
    spent,
    remaining,
    percent: Number(percent.toFixed(2)),
    status: statusFor(percent, budget.alert_threshold),
    daily_allowance: daysLeft > 0 ? Number((Math.max(remaining, 0) / daysLeft).toFixed(2)) : 0,
  };
}

async function loadBudgetsWithSpent(userId, month, firstDay, { familyId = null, onlyOwn = false } = {}) {
  const bounds = monthBounds(month, firstDay);

  const params = [];
  let where;
  if (onlyOwn) {
    where = 'b.user_id = ?';
    params.push(userId);
  } else {
    const visibility = await scope.visibilityClause(userId, 'b');
    where = visibility.sql;
    params.push(...visibility.params);
  }

  let sql = `SELECT b.*, CASE WHEN pc.name IS NULL THEN c.name ELSE CONCAT(pc.name, ' › ', c.name) END AS category_name,
                    c.color AS category_color, c.icon AS category_icon
             FROM budgets b
             JOIN categories c ON c.id = b.category_id
             LEFT JOIN categories pc ON pc.id = c.parent_id
             WHERE ${where} AND b.budget_month = ?`;
  params.push(month);

  if (familyId) {
    sql += ' AND b.family_id = ?';
    params.push(familyId);
  }
  sql += ' ORDER BY c.name';

  const [budgets] = await db.query(sql, params);
  if (budgets.length === 0) return { bounds, rows: [] };

  const categoryIds = budgets.map(b => Number(b.category_id));
  const [spentMap, children] = await Promise.all([
    spentByCategory(userId, bounds),
    childrenOf(categoryIds),
  ]);

  const daysLeft = daysLeftIn(bounds);
  const rows = budgets.map(budget => {
    const categoryId = Number(budget.category_id);
    let spent = spentMap.get(categoryId) || 0;
    for (const childId of children.get(categoryId) || []) spent += spentMap.get(childId) || 0;
    return decorate(budget, Number(spent.toFixed(2)), daysLeft);
  });

  return { bounds, rows };
}

async function loadBudget(userId, id) {
  const [rows] = await db.query(
    `SELECT b.*, CASE WHEN pc.name IS NULL THEN c.name ELSE CONCAT(pc.name, ' › ', c.name) END AS category_name,
            c.color AS category_color, c.icon AS category_icon
     FROM budgets b JOIN categories c ON c.id = b.category_id
     LEFT JOIN categories pc ON pc.id = c.parent_id
     WHERE b.id = ? AND b.user_id = ?`,
    [id, userId]
  );
  if (rows.length === 0) throw Object.assign(new Error('Orçamento não encontrado.'), { status: 404 });
  return rows[0];
}

// GET / — orçamentos do mês com gasto, percentual, status e totais.
// Tambem traz as faturas de cartao com vencimento no mes: o "previsto cartao"
// e o valor da fatura que sera debitada; o "gasto cartao" so soma o que foi
// efetivamente pago.
router.get('/', asyncHandler(async (req, res) => {
  const month = assertMonth(req.query.month || dates.currentMonth());
  const familyId = req.query.family_id || null;

  const { bounds, rows } = await loadBudgetsWithSpent(req.userId, month, req.user.first_day_of_month, { familyId });

  const budgeted = rows.reduce((sum, r) => sum + r.amount, 0);
  const spent = rows.reduce((sum, r) => sum + r.spent, 0);

  const [invoiceRows] = await db.query(
    `SELECT i.id, i.card_id, i.reference_month, i.total_amount, i.paid_amount,
            i.due_date, i.closing_date, i.status, c.name AS card_name, c.color AS card_color
     FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE i.user_id = ? AND i.due_date BETWEEN ? AND ? AND i.status <> 'cancelled'
       AND (i.total_amount > 0 OR i.paid_amount > 0)
     ORDER BY i.due_date`,
    [req.userId, bounds.start, bounds.end]
  );
  const cardInvoices = invoiceRows.map(i => ({
    ...i,
    total_amount: Number(i.total_amount),
    paid_amount: Number(i.paid_amount),
    remaining: Number((Number(i.total_amount) - Number(i.paid_amount)).toFixed(2)),
  }));
  const cardForecast = cardInvoices.reduce((s, i) => s + i.total_amount, 0);
  const cardSpent = cardInvoices.reduce((s, i) => s + i.paid_amount, 0);

  // Categorias das compras que compoem as faturas do mes: total geral e por fatura.
  let cardCategories = [];
  if (cardInvoices.length > 0) {
    const ids = cardInvoices.map(i => i.id);
    const placeholders = ids.map(() => '?').join(',');
    const [catRows] = await db.query(
      `SELECT t.invoice_id,
              COALESCE(IF(p.name IS NULL, c.name, CONCAT(p.name, ' › ', c.name)), 'Sem categoria') AS category_name,
              c.color AS category_color,
              SUM(CASE WHEN t.is_refund THEN -t.amount ELSE t.amount END) AS total
       FROM transactions t
       LEFT JOIN categories c ON c.id = t.category_id
       LEFT JOIN categories p ON p.id = c.parent_id
       WHERE t.invoice_id IN (${placeholders})
         AND t.deleted_at IS NULL AND t.status <> 'cancelled'
       GROUP BY t.invoice_id, c.id, c.name, c.color
       ORDER BY total DESC`,
      ids
    );

    const byInvoice = new Map();
    const aggregate = new Map();
    for (const r of catRows) {
      const entry = {
        category_name: r.category_name,
        category_color: r.category_color,
        total: Number(r.total),
      };
      const key = Number(r.invoice_id);
      if (!byInvoice.has(key)) byInvoice.set(key, []);
      byInvoice.get(key).push(entry);
      const agg = aggregate.get(entry.category_name) || 0;
      aggregate.set(entry.category_name, agg + entry.total);
    }
    for (const inv of cardInvoices) {
      inv.categories = byInvoice.get(Number(inv.id)) || [];
    }
    cardCategories = [...aggregate.entries()]
      .map(([category_name, total]) => ({ category_name, total: Number(total.toFixed(2)) }))
      .sort((a, b) => b.total - a.total);
  }

  const forecastTotal = budgeted + cardForecast;
  const spentTotal = spent + cardSpent;

  res.json({
    month,
    budgets: rows,
    // O app antigo lê a lista direta; mantemos ambos os formatos.
    items: rows,
    card_invoices: cardInvoices,
    card_categories: cardCategories,
    totals: {
      budgeted: Number(budgeted.toFixed(2)),
      spent: Number(spent.toFixed(2)),
      card_forecast: Number(cardForecast.toFixed(2)),
      card_spent: Number(cardSpent.toFixed(2)),
      forecast_total: Number(forecastTotal.toFixed(2)),
      spent_total: Number(spentTotal.toFixed(2)),
      remaining: Number((forecastTotal - spentTotal).toFixed(2)),
      percent: forecastTotal > 0 ? Number(((spentTotal / forecastTotal) * 100).toFixed(2)) : 0,
    },
  });
}));

// POST /copy — replica os orçamentos de um mês no outro (início de mês).
router.post('/copy', asyncHandler(async (req, res) => {
  const fromMonth = assertMonth(req.body?.from_month, 'from_month');
  const toMonth = assertMonth(req.body?.to_month, 'to_month');
  if (fromMonth === toMonth) throw badRequest('Os meses de origem e destino devem ser diferentes.');
  const overwrite = parseBool(req.body?.overwrite) === true;

  const [source] = await db.query(
    'SELECT * FROM budgets WHERE user_id = ? AND budget_month = ?',
    [req.userId, fromMonth]
  );
  if (source.length === 0) throw badRequest('Nenhum orçamento encontrado no mês de origem.');

  const [existing] = await db.query(
    'SELECT category_id FROM budgets WHERE user_id = ? AND budget_month = ?',
    [req.userId, toMonth]
  );
  const taken = new Set(existing.map(r => Number(r.category_id)));

  let created = 0;
  let updated = 0;
  let skipped = 0;

  for (const budget of source) {
    const categoryId = Number(budget.category_id);
    if (taken.has(categoryId)) {
      if (!overwrite) { skipped++; continue; }
      await db.query(
        `UPDATE budgets SET amount = ?, alert_threshold = ?, rollover = ?, family_id = ?
         WHERE user_id = ? AND category_id = ? AND budget_month = ?`,
        [budget.amount, budget.alert_threshold, budget.rollover, budget.family_id, req.userId, categoryId, toMonth]
      );
      updated++;
      continue;
    }

    await db.query(
      `INSERT INTO budgets (user_id, category_id, budget_month, amount, alert_threshold, rollover, family_id)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [req.userId, categoryId, toMonth, budget.amount, budget.alert_threshold, budget.rollover, budget.family_id]
    );
    created++;
  }

  await audit(req.userId, 'budget', null, 'create', { copy: { from: fromMonth, to: toMonth, created, updated, skipped } });
  res.json({ message: 'Orçamentos copiados.', from_month: fromMonth, to_month: toMonth, created, updated, skipped });
}));

// GET /history — orçado x gasto de uma categoria nos últimos meses.
router.get('/history', asyncHandler(async (req, res) => {
  const categoryId = Number(req.query.category_id);
  if (!categoryId) throw badRequest('Informe category_id.');
  const months = Math.min(Math.max(Number(req.query.months) || 12, 1), 36);

  const [categories] = await db.query(
    'SELECT id, name FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL)',
    [categoryId, req.userId]
  );
  if (categories.length === 0) throw Object.assign(new Error('Categoria não encontrada.'), { status: 404 });

  const children = await childrenOf([categoryId]);
  const ids = [categoryId, ...(children.get(categoryId) || [])];
  const placeholders = ids.map(() => '?').join(', ');

  const current = dates.currentMonth();
  const monthsList = [];
  for (let i = months - 1; i >= 0; i--) monthsList.push(dates.addMonthsToMonth(current, -i));

  const firstBounds = monthBounds(monthsList[0], req.user.first_day_of_month);
  const lastBounds = monthBounds(monthsList[monthsList.length - 1], req.user.first_day_of_month);

  const visibility = await scope.visibilityClause(req.userId, 't');
  const [transactions] = await db.query(
    `SELECT t.date, t.amount FROM transactions t
     WHERE ${visibility.sql}
       AND t.category_id IN (${placeholders})
       AND t.type = 'expense' AND t.deleted_at IS NULL AND t.status <> 'cancelled'
       AND t.date BETWEEN ? AND ?`,
    [...visibility.params, ...ids, firstBounds.start, lastBounds.end]
  );

  const [budgets] = await db.query(
    `SELECT budget_month, amount FROM budgets
     WHERE user_id = ? AND category_id = ? AND budget_month BETWEEN ? AND ?`,
    [req.userId, categoryId, monthsList[0], monthsList[monthsList.length - 1]]
  );
  const budgetMap = new Map(budgets.map(b => [b.budget_month, Number(b.amount)]));

  const history = monthsList.map(month => {
    const bounds = monthBounds(month, req.user.first_day_of_month);
    const spent = transactions
      .filter(t => t.date >= bounds.start && t.date <= bounds.end)
      .reduce((sum, t) => sum + Number(t.amount), 0);
    const budgeted = budgetMap.get(month) || 0;
    return {
      month,
      budgeted,
      spent: Number(spent.toFixed(2)),
      percent: budgeted > 0 ? Number(((spent / budgeted) * 100).toFixed(2)) : 0,
    };
  });

  res.json({ category_id: categoryId, category_name: categories[0].name, months: monthsList.length, history });
}));

// POST /check-alerts — verifica apenas os orçamentos do usuário atual (spec §14).
router.post('/check-alerts', asyncHandler(async (req, res) => {
  const month = assertMonth(req.body?.month || req.query.month || dates.currentMonth());
  const { rows } = await loadBudgetsWithSpent(req.userId, month, req.user.first_day_of_month, { onlyOwn: true });

  let alerts = 0;

  for (const budget of rows) {
    if (budget.percent >= 100) {
      const id = await notify({
        userId: req.userId,
        type: 'budget_over',
        title: `Orçamento estourado: ${budget.category_name}`,
        message: `Você gastou R$ ${budget.spent.toFixed(2)} de R$ ${budget.amount.toFixed(2)} (${budget.percent.toFixed(0)}%).`,
        severity: 'critical',
        entity: 'budget',
        entityId: budget.id,
        dedupeKey: `budget_over:${budget.id}:${month}`,
      });
      if (id) {
        alerts++;
        await db.query('UPDATE budgets SET notified_over_at = NOW() WHERE id = ?', [budget.id]);
      }
    } else if (budget.percent >= budget.alert_threshold) {
      const id = await notify({
        userId: req.userId,
        type: 'budget_near',
        title: `Orçamento em ${budget.percent.toFixed(0)}%: ${budget.category_name}`,
        message: `Restam R$ ${budget.remaining.toFixed(2)} do orçamento de ${budget.category_name} neste mês.`,
        severity: 'warning',
        entity: 'budget',
        entityId: budget.id,
        dedupeKey: `budget_near:${budget.id}:${month}`,
      });
      if (id) {
        alerts++;
        await db.query('UPDATE budgets SET notified_near_at = NOW() WHERE id = ?', [budget.id]);
      }
    }
  }

  res.json({ month, checked: rows.length, alerts });
}));

// POST / — cria orçamento da categoria no mês.
router.post('/', asyncHandler(async (req, res) => {
  const { category_id, amount, budget_month, alert_threshold, rollover, family_id } = req.body || {};
  if (!category_id) throw badRequest('Categoria é obrigatória.');
  if (amount === undefined || amount === null || Number(amount) <= 0) {
    throw badRequest('Valor do orçamento deve ser maior que zero.');
  }
  const month = assertMonth(budget_month || dates.currentMonth(), 'budget_month');

  const [categories] = await db.query(
    'SELECT id, type FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL)',
    [category_id, req.userId]
  );
  if (categories.length === 0) throw Object.assign(new Error('Categoria não encontrada.'), { status: 404 });
  if (categories[0].type !== 'expense') throw badRequest('Só é possível orçar categorias de despesa.');

  if (family_id) await scope.assertCanUseFamily(req.userId, family_id);

  const threshold = alert_threshold === undefined || alert_threshold === null ? 80 : Number(alert_threshold);
  if (Number.isNaN(threshold) || threshold < 1 || threshold > 100) {
    throw badRequest('O limite de alerta deve estar entre 1 e 100.');
  }

  let insertId;
  try {
    const [result] = await db.query(
      `INSERT INTO budgets (user_id, category_id, budget_month, amount, alert_threshold, rollover, family_id)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [req.userId, category_id, month, amount, threshold, parseBool(rollover) === true, family_id || null]
    );
    insertId = result.insertId;
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      throw Object.assign(new Error('Já existe orçamento para esta categoria neste mês.'), { status: 409 });
    }
    throw err;
  }

  const budget = await loadBudget(req.userId, insertId);
  await audit(req.userId, 'budget', insertId, 'create', budget);
  res.status(201).json(budget);
}));

// PUT /:id — valor, limite de alerta e rollover.
router.put('/:id', asyncHandler(async (req, res) => {
  const before = await loadBudget(req.userId, req.params.id);
  const { amount, alert_threshold, rollover } = req.body || {};

  if (amount !== undefined && Number(amount) <= 0) throw badRequest('Valor do orçamento deve ser maior que zero.');
  const threshold = alert_threshold === undefined ? Number(before.alert_threshold) : Number(alert_threshold);
  if (Number.isNaN(threshold) || threshold < 1 || threshold > 100) {
    throw badRequest('O limite de alerta deve estar entre 1 e 100.');
  }

  await db.query(
    `UPDATE budgets SET amount = ?, alert_threshold = ?, rollover = ?,
            notified_near_at = NULL, notified_over_at = NULL
     WHERE id = ? AND user_id = ?`,
    [
      amount === undefined ? before.amount : amount,
      threshold,
      rollover === undefined ? !!before.rollover : parseBool(rollover) === true,
      before.id, req.userId,
    ]
  );

  const after = await loadBudget(req.userId, before.id);
  await audit(req.userId, 'budget', before.id, 'update', { before, after });
  res.json(after);
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  const allMonths = parseBool(req.query.all_months);
  const budget = await loadBudget(req.userId, req.params.id);

  if (allMonths) {
    await db.query(
      'DELETE FROM budgets WHERE user_id = ? AND category_id = ?',
      [req.userId, budget.category_id]
    );
    await audit(req.userId, 'budget', budget.id, 'delete', { ...budget, all_months: true });
    res.json({ message: 'Previsões da categoria removidas.' });
  } else {
    await db.query('DELETE FROM budgets WHERE id = ? AND user_id = ?', [budget.id, req.userId]);
    await audit(req.userId, 'budget', budget.id, 'delete', budget);
    res.json({ message: 'Previsão removida.' });
  }
}));

module.exports = router;
module.exports.monthBounds = monthBounds;
