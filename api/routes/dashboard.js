// Dashboard consolidado (spec §13).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const jobs = require('../lib/jobs');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const today = dates.toIsoDate(new Date());
  const month = today.slice(0, 7);
  const range = dates.monthRange(month);
  const [income] = await db.query(
    "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE user_id = ? AND type = 'income' AND deleted_at IS NULL AND date >= ? AND date <= ?",
    [req.userId, range.start, range.end]
  );
  const [expense] = await db.query(
    "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE user_id = ? AND type = 'expense' AND deleted_at IS NULL AND date >= ? AND date <= ?",
    [req.userId, range.start, range.end]
  );
  const [accounts] = await db.query(
    'SELECT COALESCE(SUM(current_balance), 0) AS total FROM accounts WHERE user_id = ? AND active = TRUE',
    [req.userId]
  );
  const [cards] = await db.query(
    `SELECT COALESCE(SUM(total_amount - paid_amount), 0) AS total
     FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE c.user_id = ? AND i.status != 'paid'`,
    [req.userId]
  );
  const [budgets] = await db.query(
    `SELECT b.*, COALESCE(SUM(t.amount), 0) AS spent
     FROM budgets b
     LEFT JOIN transactions t ON t.category_id = b.category_id AND t.type = 'expense' AND t.deleted_at IS NULL AND t.date >= ? AND t.date <= ?
     WHERE b.user_id = ? AND b.budget_month = ?
     GROUP BY b.id`,
    [range.start, range.end, req.userId, month]
  );
  const net = await jobs.netWorthTotals(req.userId);
  res.json({
    month,
    income: Number(income[0].total),
    expense: Number(expense[0].total),
    balance: Number(accounts[0].total),
    card_debt: Number(cards[0].total),
    budgets: budgets.map(b => ({ ...b, percent: b.amount ? Math.round((b.spent / b.amount) * 100) : 0 })),
    net_worth: net.net_worth
  });
}));

module.exports = router;
