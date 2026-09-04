// Parcelamentos e parcelas (spec §7).
//
// Dois modelos convivem:
// - Parcelamento de CARTÃO: todas as transações já nascem lançadas nas faturas
//   (criadas em POST /cards/:id/purchases). Aqui só administramos as parcelas.
// - Parcelamento de CONTA: nada é lançado na criação; a transação nasce quando
//   a parcela é paga, porque só nesse momento o dinheiro sai da conta.
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const dates = require('../lib/dates');
const ledger = require('../lib/ledger');

const router = express.Router();
router.use(authenticate);

function fail(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

function round2(value) {
  return Math.round(Number(value) * 100) / 100;
}

// Sobra de arredondamento vai na última parcela para fechar o total exato.
function splitAmount(total, count) {
  const base = round2(Number(total) / count);
  const parts = new Array(count).fill(base);
  parts[count - 1] = round2(Number(total) - base * (count - 1));
  return parts;
}

const LIST_SELECT = `
  SELECT i.*,
         cc.name AS card_name, a.name AS account_name, cat.name AS category_name,
         COALESCE((SELECT SUM(ii.amount) FROM installment_items ii
                   WHERE ii.installment_id = i.id AND ii.paid = TRUE), 0) AS paid_amount,
         COALESCE((SELECT SUM(ii.amount) FROM installment_items ii
                   WHERE ii.installment_id = i.id AND ii.paid = FALSE AND ii.cancelled = FALSE), 0) AS remaining_amount,
         (SELECT MIN(ii.due_date) FROM installment_items ii
          WHERE ii.installment_id = i.id AND ii.paid = FALSE AND ii.cancelled = FALSE) AS next_due_date
  FROM installments i
  LEFT JOIN credit_cards cc ON cc.id = i.card_id
  LEFT JOIN accounts a ON a.id = i.account_id
  LEFT JOIN categories cat ON cat.id = i.category_id
`;

function decorate(row) {
  return {
    ...row,
    paid_amount: round2(row.paid_amount),
    remaining_amount: round2(row.remaining_amount),
    progress_label: `${row.paid_installments || 0}/${row.total_installments}`,
  };
}

async function findInstallment(userId, id) {
  const [rows] = await db.query(`${LIST_SELECT} WHERE i.id = ? AND i.user_id = ?`, [id, userId]);
  if (rows.length === 0) throw fail('Parcelamento não encontrado.', 404);
  return rows[0];
}

async function itemsOf(connOrDb, installmentId) {
  const [rows] = await connOrDb.query(
    'SELECT * FROM installment_items WHERE installment_id = ? ORDER BY number',
    [installmentId]
  );
  return rows;
}

// -------------------------------------------------------------------- consultas

router.get('/summary', asyncHandler(async (req, res) => {
  const [totals] = await db.query(
    `SELECT
       SUM(CASE WHEN i.status = 'active' THEN 1 ELSE 0 END) AS active_count,
       COALESCE(SUM(CASE WHEN i.status = 'active' THEN i.total_amount ELSE 0 END), 0) AS total_amount
     FROM installments i WHERE i.user_id = ?`,
    [req.userId]
  );

  const [amounts] = await db.query(
    `SELECT
       COALESCE(SUM(CASE WHEN ii.paid = TRUE THEN ii.amount ELSE 0 END), 0) AS paid_amount,
       COALESCE(SUM(CASE WHEN ii.paid = FALSE AND ii.cancelled = FALSE THEN ii.amount ELSE 0 END), 0) AS remaining_amount
     FROM installment_items ii
     JOIN installments i ON i.id = ii.installment_id
     WHERE i.user_id = ? AND i.status = 'active'`,
    [req.userId]
  );

  const [byMonth] = await db.query(
    `SELECT DATE_FORMAT(ii.due_date, '%Y-%m') AS month, COALESCE(SUM(ii.amount), 0) AS amount
     FROM installment_items ii
     JOIN installments i ON i.id = ii.installment_id
     WHERE i.user_id = ? AND ii.paid = FALSE AND ii.cancelled = FALSE
       AND ii.due_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
       AND ii.due_date < DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 12 MONTH)
     GROUP BY month`,
    [req.userId]
  );

  const map = new Map(byMonth.map(r => [r.month, round2(r.amount)]));
  const monthly = [];
  const start = dates.currentMonth();
  for (let index = 0; index < 12; index++) {
    const month = dates.addMonthsToMonth(start, index);
    monthly.push({ month, amount: map.get(month) || 0 });
  }

  res.json({
    active_installments: Number(totals[0].active_count || 0),
    total_amount: round2(totals[0].total_amount),
    paid_amount: round2(amounts[0].paid_amount),
    remaining_amount: round2(amounts[0].remaining_amount),
    monthly_commitment: monthly,
  });
}));

router.get('/', asyncHandler(async (req, res) => {
  const { status, card_id, account_id } = req.query;
  const params = [req.userId];
  let sql = `${LIST_SELECT} WHERE i.user_id = ?`;

  if (status) {
    sql += ' AND i.status = ?';
    params.push(status);
  }
  if (card_id) {
    sql += ' AND i.card_id = ?';
    params.push(card_id);
  }
  if (account_id) {
    sql += ' AND i.account_id = ?';
    params.push(account_id);
  }
  sql += ' ORDER BY i.status, i.start_date DESC, i.id DESC';

  const [rows] = await db.query(sql, params);
  res.json(rows.map(decorate));
}));

router.get('/:id', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);
  const items = await itemsOf(db, installment.id);
  res.json({ ...decorate(installment), items });
}));

// ---------------------------------------------------------------------- criação

router.post('/', asyncHandler(async (req, res) => {
  const {
    description, total_amount, total_installments, start_date,
    account_id = null, category_id = null, type = 'expense', notes = null,
  } = req.body;

  if (req.body.card_id) {
    throw fail('Para parcelar uma compra no cartão use POST /cards/:id/purchases — assim as parcelas entram nas faturas corretas.');
  }
  if (!description) throw fail('Descrição é obrigatória.');
  if (!total_amount || Number(total_amount) <= 0) throw fail('Informe o valor total do parcelamento.');
  if (!start_date) throw fail('Informe a data da primeira parcela.');
  const count = Number(total_installments);
  if (!Number.isInteger(count) || count < 1 || count > 480) throw fail('Número de parcelas inválido.');
  if (!['income', 'expense'].includes(type)) throw fail('Tipo deve ser income ou expense.');

  const result = await withTransaction(async conn => {
    const parts = splitAmount(total_amount, count);
    const [inserted] = await conn.query(
      `INSERT INTO installments
         (user_id, account_id, category_id, description, total_amount, total_installments,
          current_installment, paid_installments, amount, type, start_date, purchase_date, status, notes)
       VALUES (?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?, 'active', ?)`,
      [req.userId, account_id, category_id, description, round2(total_amount), count, parts[0], type, start_date, start_date, notes]
    );
    const installmentId = inserted.insertId;

    for (let index = 0; index < count; index++) {
      await conn.query(
        'INSERT INTO installment_items (installment_id, number, due_date, amount) VALUES (?, ?, ?, ?)',
        [installmentId, index + 1, dates.toIsoDate(dates.addMonths(start_date, index)), parts[index]]
      );
    }

    const [rows] = await conn.query('SELECT * FROM installments WHERE id = ?', [installmentId]);
    return { installment: rows[0], items: await itemsOf(conn, installmentId) };
  });

  await audit(req.userId, 'installment', result.installment.id, 'create', { total: round2(total_amount), parcelas: count });
  res.status(201).json({
    message: 'Parcelamento criado. As transações serão lançadas conforme cada parcela for paga.',
    ...result,
  });
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);
  const pick = (value, fallback) => (value === undefined ? fallback : value);

  const merged = {
    description: pick(req.body.description, installment.description),
    category_id: pick(req.body.category_id, installment.category_id),
    account_id: pick(req.body.account_id, installment.account_id),
    notes: pick(req.body.notes, installment.notes),
  };

  const newCount = req.body.total_installments === undefined ? null : Number(req.body.total_installments);
  if (newCount !== null && newCount !== installment.total_installments) {
    if (!Number.isInteger(newCount) || newCount < 1 || newCount > 480) throw fail('Número de parcelas inválido.');
    if (installment.card_id) {
      throw fail('Parcelas de cartão já estão lançadas nas faturas. Use POST /installments/:id/cancel-future e lance a compra novamente para mudar o número de parcelas.');
    }
  }

  await withTransaction(async conn => {
    await conn.query(
      'UPDATE installments SET description = ?, category_id = ?, account_id = ?, notes = ? WHERE id = ? AND user_id = ?',
      [merged.description, merged.category_id, merged.account_id, merged.notes, installment.id, req.userId]
    );

    if (newCount === null || newCount === installment.total_installments) return;

    // Alteração do parcelamento: parcelas já pagas são intocáveis (elas geraram
    // transações e afetaram saldos). O saldo restante — total menos o que já foi
    // pago — é redistribuído nas parcelas novas, mês a mês a partir da última paga.
    const items = await itemsOf(conn, installment.id);
    const paidItems = items.filter(i => i.paid);
    if (newCount <= paidItems.length) {
      throw fail(`Já existem ${paidItems.length} parcela(s) paga(s): o novo total precisa ser maior que isso.`);
    }

    const paidSum = paidItems.reduce((sum, item) => sum + Number(item.amount), 0);
    const remaining = round2(Number(installment.total_amount) - paidSum);
    if (remaining <= 0) throw fail('Não há saldo restante para redistribuir.');

    const openCount = newCount - paidItems.length;
    const parts = splitAmount(remaining, openCount);

    await conn.query('DELETE FROM installment_items WHERE installment_id = ? AND paid = FALSE', [installment.id]);

    const baseDate = paidItems.length > 0
      ? paidItems[paidItems.length - 1].due_date
      : dates.toIsoDate(dates.addMonths(installment.start_date, -1));

    for (let index = 0; index < openCount; index++) {
      await conn.query(
        'INSERT INTO installment_items (installment_id, number, due_date, amount) VALUES (?, ?, ?, ?)',
        [
          installment.id,
          paidItems.length + index + 1,
          dates.toIsoDate(dates.addMonths(baseDate, index + 1)),
          parts[index],
        ]
      );
    }

    await conn.query(
      'UPDATE installments SET total_installments = ?, amount = ? WHERE id = ?',
      [newCount, parts[0], installment.id]
    );
    await ledger.syncInstallmentProgress(conn, installment.id);
  });

  const updated = await findInstallment(req.userId, installment.id);
  await audit(req.userId, 'installment', installment.id, 'update', { ...merged, total_installments: newCount });
  res.json({ ...decorate(updated), items: await itemsOf(db, installment.id) });
}));

// ------------------------------------------------------------ pagar / desfazer

router.post('/:id/items/:number/pay', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);

  const result = await withTransaction(async conn => {
    const [rows] = await conn.query(
      'SELECT * FROM installment_items WHERE installment_id = ? AND number = ?',
      [installment.id, req.params.number]
    );
    if (rows.length === 0) throw fail('Parcela não encontrada.', 404);
    const item = rows[0];
    if (item.paid) throw fail('Parcela já está paga.');
    if (item.cancelled) throw fail('Parcela cancelada não pode ser paga.');

    const paidAt = req.body.date || dates.toIsoDate(new Date());
    let transactionId = item.transaction_id;

    // Parcela de cartão já tem transação na fatura: aqui só marcamos como paga,
    // sem lançar de novo (o dinheiro sai no pagamento da fatura).
    if (!transactionId) {
      const accountId = req.body.account_id || installment.account_id;
      const transaction = await ledger.createTransaction(conn, req.userId, {
        account_id: accountId,
        category_id: installment.category_id,
        type: installment.type,
        amount: item.amount,
        date: paidAt,
        description: `${installment.description || 'Parcelamento'} (${item.number}/${installment.total_installments})`,
        installment_id: installment.id,
        installment_number: item.number,
        source: 'installment',
      });
      transactionId = transaction.id;
    }

    await conn.query(
      'UPDATE installment_items SET paid = TRUE, paid_at = ?, transaction_id = ? WHERE id = ?',
      [paidAt, transactionId, item.id]
    );
    await ledger.syncInstallmentProgress(conn, installment.id);

    return { transaction_id: transactionId, paid_at: paidAt, number: item.number, amount: round2(item.amount) };
  });

  await audit(req.userId, 'installment_item', installment.id, 'update', { parcela: result.number, acao: 'pagamento' });
  const updated = await findInstallment(req.userId, installment.id);
  res.json({ message: `Parcela ${result.number} paga.`, payment: result, installment: decorate(updated) });
}));

router.post('/:id/items/:number/unpay', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);

  await withTransaction(async conn => {
    const [rows] = await conn.query(
      'SELECT * FROM installment_items WHERE installment_id = ? AND number = ?',
      [installment.id, req.params.number]
    );
    if (rows.length === 0) throw fail('Parcela não encontrada.', 404);
    const item = rows[0];
    if (!item.paid) throw fail('Parcela não está paga.');

    // Em parcelamento de conta a transação é excluída (reverte o saldo). Em
    // parcelamento de cartão a transação pertence à fatura e permanece.
    if (item.transaction_id && !installment.card_id) {
      await ledger.deleteTransaction(conn, req.userId, item.transaction_id);
    }

    await conn.query(
      `UPDATE installment_items SET paid = FALSE, paid_at = NULL,
         transaction_id = ${installment.card_id ? 'transaction_id' : 'NULL'}
       WHERE id = ?`,
      [item.id]
    );
    await conn.query(`UPDATE installments SET status = 'active', active = TRUE WHERE id = ? AND status = 'completed'`, [installment.id]);
    await ledger.syncInstallmentProgress(conn, installment.id);
  });

  await audit(req.userId, 'installment_item', installment.id, 'update', { parcela: Number(req.params.number), acao: 'estorno' });
  const updated = await findInstallment(req.userId, installment.id);
  res.json({ message: 'Pagamento da parcela desfeito.', installment: decorate(updated) });
}));

router.post('/:id/anticipate', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);
  const numbers = Array.isArray(req.body.numbers) ? req.body.numbers.map(Number).filter(Boolean) : [];
  if (numbers.length === 0) throw fail('Informe as parcelas a antecipar em "numbers".');

  const discount = round2(req.body.discount || 0);
  const paidAt = req.body.date || dates.toIsoDate(new Date());

  const result = await withTransaction(async conn => {
    const [items] = await conn.query(
      `SELECT * FROM installment_items
       WHERE installment_id = ? AND number IN (${numbers.map(() => '?').join(',')})
       ORDER BY number`,
      [installment.id, ...numbers]
    );
    if (items.length !== numbers.length) throw fail('Alguma das parcelas informadas não existe.', 404);

    const pending = items.filter(i => !i.paid && !i.cancelled);
    if (pending.length === 0) throw fail('As parcelas informadas já estão pagas ou canceladas.');

    const gross = round2(pending.reduce((sum, item) => sum + Number(item.amount), 0));
    if (discount < 0 || discount >= gross) throw fail('Desconto inválido para o total antecipado.');
    // Desconto absoluto rateado proporcionalmente ao valor de cada parcela.
    const factor = (gross - discount) / gross;

    let total = 0;
    const accountId = req.body.account_id || installment.account_id;

    for (const item of pending) {
      const value = round2(Number(item.amount) * factor);
      let transactionId = item.transaction_id;
      const note = discount > 0
        ? `Antecipação de parcelas com desconto de R$ ${discount.toFixed(2)} sobre R$ ${gross.toFixed(2)}.`
        : 'Antecipação de parcelas.';

      if (transactionId) {
        // Parcela de cartão: ajusta a transação já lançada na fatura.
        await ledger.updateTransaction(conn, req.userId, transactionId, { amount: value, date: paidAt, notes: note });
      } else {
        const transaction = await ledger.createTransaction(conn, req.userId, {
          account_id: accountId,
          category_id: installment.category_id,
          type: installment.type,
          amount: value,
          date: paidAt,
          description: `${installment.description || 'Parcelamento'} (${item.number}/${installment.total_installments}) — antecipada`,
          notes: note,
          installment_id: installment.id,
          installment_number: item.number,
          source: 'installment',
        });
        transactionId = transaction.id;
      }

      await conn.query(
        'UPDATE installment_items SET paid = TRUE, paid_at = ?, transaction_id = ?, amount = ? WHERE id = ?',
        [paidAt, transactionId, value, item.id]
      );
      total = round2(total + value);
    }

    await ledger.syncInstallmentProgress(conn, installment.id);
    return { anticipated: pending.map(i => i.number), gross, discount, total_paid: total };
  });

  await audit(req.userId, 'installment', installment.id, 'update', { acao: 'antecipacao', ...result });
  const updated = await findInstallment(req.userId, installment.id);
  res.json({ message: 'Parcelas antecipadas.', ...result, installment: decorate(updated) });
}));

router.post('/:id/cancel-future', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);

  const result = await withTransaction(async conn => {
    const [items] = await conn.query(
      'SELECT * FROM installment_items WHERE installment_id = ? AND paid = FALSE AND cancelled = FALSE ORDER BY number',
      [installment.id]
    );
    if (items.length === 0) throw fail('Não há parcelas em aberto para cancelar.');

    for (const item of items) {
      // Parcelas de cartão já estavam lançadas nas faturas: excluir a transação
      // é o que devolve o valor ao limite/fatura.
      if (item.transaction_id) {
        await ledger.deleteTransaction(conn, req.userId, item.transaction_id);
      }
      await conn.query('UPDATE installment_items SET cancelled = TRUE, transaction_id = NULL WHERE id = ?', [item.id]);
    }

    await ledger.syncInstallmentProgress(conn, installment.id);
    const [open] = await conn.query(
      'SELECT COUNT(*) AS total FROM installment_items WHERE installment_id = ? AND paid = FALSE AND cancelled = FALSE',
      [installment.id]
    );
    if (open[0].total === 0) {
      await conn.query(`UPDATE installments SET status = 'completed', active = FALSE WHERE id = ?`, [installment.id]);
    }

    return { cancelled: items.map(i => i.number) };
  });

  await audit(req.userId, 'installment', installment.id, 'update', { acao: 'cancelamento_futuras', ...result });
  const updated = await findInstallment(req.userId, installment.id);
  res.json({ message: `${result.cancelled.length} parcela(s) futura(s) cancelada(s).`, ...result, installment: decorate(updated) });
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  const installment = await findInstallment(req.userId, req.params.id);

  const removed = await withTransaction(async conn => {
    const [transactions] = await conn.query(
      'SELECT id FROM transactions WHERE installment_id = ? AND user_id = ? AND deleted_at IS NULL',
      [installment.id, req.userId]
    );
    for (const transaction of transactions) {
      await ledger.deleteTransaction(conn, req.userId, transaction.id);
    }
    await conn.query('DELETE FROM installment_items WHERE installment_id = ?', [installment.id]);
    await conn.query('DELETE FROM installments WHERE id = ? AND user_id = ?', [installment.id, req.userId]);
    return transactions.length;
  });

  await audit(req.userId, 'installment', installment.id, 'delete', { transacoes_excluidas: removed });
  res.json({ message: `Parcelamento excluído junto com ${removed} lançamento(s) vinculado(s).` });
}));

module.exports = router;
