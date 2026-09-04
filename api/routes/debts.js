// Dívidas e empréstimos (spec §18).
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { requireFeature } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const ledger = require('../lib/ledger');
const scope = require('../lib/scope');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

const TYPES = ['loan','financing','personal','card','installment','overdraft','other'];
const STATUSES = ['active','paid','renegotiated','defaulted'];

function badRequest(message) { return Object.assign(new Error(message), { status: 400 }); }

router.get('/', asyncHandler(async (req, res) => {
  const q = req.query;
  const visibility = await scope.visibilityClause(req.userId, 'd');
  const conditions = ['d.deleted_at IS NULL', visibility.sql];
  const params = [...visibility.params];
  if (q.status && STATUSES.includes(q.status)) { conditions.push('d.status = ?'); params.push(q.status); }
  if (q.type && TYPES.includes(q.type)) { conditions.push('d.type = ?'); params.push(q.type); }
  const [rows] = await db.query(
    `SELECT d.* FROM debts d WHERE ${conditions.join(' AND ')} ORDER BY d.next_due_date ASC, d.id DESC`,
    params
  );
  res.json({ debts: rows.map(r => ({
    ...r,
    remaining: Number(r.original_amount) - Number(r.paid_amount),
    percent_paid: Number(r.original_amount) ? Math.round((Number(r.paid_amount) / Number(r.original_amount)) * 100) : 0,
    remaining_installments: (r.total_installments || 0) - (r.paid_installments || 0),
    days_to_due: r.next_due_date ? dates.daysBetween(dates.toIsoDate(new Date()), dates.toIsoDate(r.next_due_date)) : null,
    is_overdue: r.next_due_date ? new Date(r.next_due_date) < new Date() : false
  }))});
}));

router.get('/summary', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    `SELECT status, type, COUNT(*) AS count, SUM(original_amount) AS total, SUM(paid_amount) AS paid,
            SUM(installment_amount) AS monthly_commitment
     FROM debts
     WHERE user_id = ? AND status = 'active'
     GROUP BY status, type`,
    [req.userId]
  );
  const [cardDebt] = await db.query(
    `SELECT COALESCE(SUM(total_amount - paid_amount), 0) AS total
     FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE c.user_id = ? AND i.status != 'paid'`,
    [req.userId]
  );
  res.json({
    active: rows.filter(r => r.status === 'active'),
    total_original: rows.filter(r => r.status === 'active').reduce((s, r) => s + Number(r.total), 0),
    total_paid: rows.filter(r => r.status === 'active').reduce((s, r) => s + Number(r.paid), 0),
    monthly_commitment: rows.filter(r => r.status === 'active').reduce((s, r) => s + Number(r.monthly_commitment || 0), 0),
    cards_debt: Number(cardDebt[0]?.total || 0)
  });
}));

router.post('/', requireFeature('debts'), asyncHandler(async (req, res) => {
  const b = req.body;
  if (!b.name || !b.original_amount) throw badRequest('Nome e valor original são obrigatórios.');
  if (b.type && !TYPES.includes(b.type)) throw badRequest('Tipo inválido.');
  await scope.assertCanUseFamily(req.userId, b.family_id);
  const installment = b.installment_amount || (b.total_installments ? Number(b.original_amount) / b.total_installments : null);
  let next = b.next_due_date;
  if (!next && b.due_day) {
    const today = new Date();
    const candidate = new Date(today.getFullYear(), today.getMonth(), b.due_day);
    if (candidate < today) candidate.setMonth(candidate.getMonth() + 1);
    next = dates.toIsoDate(candidate);
  }
  const [result] = await db.query(
    `INSERT INTO debts (user_id, family_id, name, type, creditor, original_amount, interest_rate, total_installments,
                        installment_amount, start_date, due_day, next_due_date, card_id, notes, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
    [req.userId, b.family_id || null, b.name, b.type || 'other', b.creditor || null, b.original_amount,
     b.interest_rate || null, b.total_installments || null, installment, b.start_date || null,
     b.due_day || null, next || null, b.card_id || null, b.notes || null]
  );
  await audit(req.userId, 'debt', result.insertId, 'create');
  res.status(201).json({ id: result.insertId, message: 'Dívida criada.' });
}));

router.put('/:id', requireFeature('debts'), asyncHandler(async (req, res) => {
  const id = req.params.id;
  const [[debt]] = await db.query('SELECT * FROM debts WHERE id = ? AND user_id = ?', [id, req.userId]);
  if (!debt) throw { status: 404, message: 'Dívida não encontrada.' };
  const b = req.body;
  const fields = ['name','type','creditor','original_amount','interest_rate','total_installments','installment_amount',
                  'start_date','due_day','next_due_date','card_id','notes','status'];
  const updates = [];
  const values = [];
  for (const f of fields) {
    if (b[f] !== undefined) { updates.push(`${f} = ?`); values.push(b[f] || null); }
  }
  if (updates.length === 0) return res.json(debt);
  values.push(id);
  await db.query(`UPDATE debts SET ${updates.join(', ')} WHERE id = ?`, values);
  await audit(req.userId, 'debt', id, 'update');
  res.json({ id, message: 'Dívida atualizada.' });
}));

router.delete('/:id', requireFeature('debts'), asyncHandler(async (req, res) => {
  const id = req.params.id;
  await withTransaction(async conn => {
    await conn.query('UPDATE transactions SET debt_id = NULL WHERE debt_id = ? AND user_id = ?', [id, req.userId]);
    await conn.query('DELETE FROM debts WHERE id = ? AND user_id = ?', [id, req.userId]);
  });
  await audit(req.userId, 'debt', id, 'delete');
  res.json({ id, message: 'Dívida removida.' });
}));

router.get('/:id', asyncHandler(async (req, res) => {
  const id = req.params.id;
  const [rows] = await db.query(
    `SELECT d.* FROM debts d
     JOIN users u ON u.id = d.user_id
     WHERE d.id = ? AND d.user_id = ?`,
    [id, req.userId]
  );
  if (rows.length === 0) throw { status: 404, message: 'Dívida não encontrada.' };
  const [payments] = await db.query('SELECT * FROM debt_payments WHERE debt_id = ? ORDER BY date ASC', [id]);
  res.json({ ...rows[0], payments });
}));

router.post('/:id/payments', requireFeature('debts'), asyncHandler(async (req, res) => {
  const id = req.params.id;
  const b = req.body;
  if (!b.amount || b.amount <= 0) throw badRequest('Informe um valor positivo.');
  const [rows] = await db.query('SELECT * FROM debts WHERE id = ? AND user_id = ?', [id, req.userId]);
  if (rows.length === 0) throw { status: 404, message: 'Dívida não encontrada.' };
  const debt = rows[0];
  const remaining = Number(debt.original_amount) - Number(debt.paid_amount);
  if (Number(b.amount) > remaining + 0.01) throw badRequest(`Valor excede o saldo restante de ${remaining.toFixed(2)}.`);
  const date = b.date || dates.toIsoDate(new Date());
  let transactionId = null;
  await withTransaction(async conn => {
    if (b.account_id) {
      const tx = await ledger.createTransaction(conn, req.userId, {
        account_id: b.account_id, category_id: null, type: 'expense', amount: b.amount, date,
        description: `Pagamento: ${debt.name}`, debt_id: id, source: 'debt_payment'
      });
      transactionId = tx.id;
    }
    const [result] = await conn.query(
      'INSERT INTO debt_payments (debt_id, amount, date, transaction_id, notes) VALUES (?, ?, ?, ?, ?)',
      [id, b.amount, date, transactionId, b.notes || null]
    );
    const paid = Number(debt.paid_amount) + Number(b.amount);
    const paidInst = Number(debt.paid_installments) + (Math.abs(Number(b.amount) - Number(debt.installment_amount || 0)) < 0.01 ? 1 : 0);
    let nextDue = debt.next_due_date;
    if (debt.due_day && nextDue && paid < Number(debt.original_amount) - 0.01) {
      const d = dates.parseDate(nextDue); d.setMonth(d.getMonth() + 1); d.setDate(debt.due_day);
      nextDue = dates.toIsoDate(d);
    }
    const status = paid >= Number(debt.original_amount) - 0.01 ? 'paid' : debt.status;
    await conn.query(
      'UPDATE debts SET paid_amount = ?, paid_installments = ?, next_due_date = ?, status = ? WHERE id = ?',
      [paid, paidInst, nextDue, status, id]
    );
    return { paymentId: result.insertId, transactionId };
  });
  await audit(req.userId, 'debt', id, 'payment');
  res.status(201).json({ message: 'Pagamento registrado.' });
}));

module.exports = router;
