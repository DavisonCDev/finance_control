// Projeção de fluxo de caixa (spec §15).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const months = Math.min(Number(req.query.months) || 12, 24);
  const [balance] = await db.query(
    'SELECT COALESCE(SUM(current_balance), 0) AS total FROM accounts WHERE user_id = ? AND active = TRUE',
    [req.userId]
  );
  let current = Number(balance[0].total);
  const projections = [];
  const today = new Date();
  for (let i = 0; i < months; i++) {
    const ref = new Date(today.getFullYear(), today.getMonth() + i, 1);
    const refStr = ref.toISOString().slice(0, 7);
    const [income] = await db.query(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE user_id = ? AND type = 'income' AND deleted_at IS NULL AND date LIKE ?",
      [req.userId, `${refStr}%`]
    );
    const [expense] = await db.query(
      "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE user_id = ? AND type = 'expense' AND deleted_at IS NULL AND date LIKE ?",
      [req.userId, `${refStr}%`]
    );
    const avgIncome = Number(income[0].total) || 0;
    const avgExpense = Number(expense[0].total) || 0;
    current += (avgIncome - avgExpense);
    projections.push({ month: refStr, income: avgIncome, expense: avgExpense, balance: Number(current.toFixed(2)) });
  }
  res.json({ current_balance: Number(balance[0].total), projections });
}));

module.exports = router;
