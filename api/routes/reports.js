const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

router.use(authenticate);

router.get('/monthly', async (req, res) => {
  const { month } = req.query;
  const targetMonth = month || new Date().toISOString().slice(0, 7);

  try {
    const [budgetRows] = await db.query(
      `SELECT b.*, c.name as category_name, c.color as category_color
       FROM budgets b
       JOIN categories c ON b.category_id = c.id
       WHERE b.user_id = ? AND b.budget_month = ?`,
      [req.userId, targetMonth]
    );

    const [spentRows] = await db.query(
      `SELECT t.category_id, c.name as category_name, c.color as category_color, SUM(t.amount) as spent
       FROM transactions t
       JOIN categories c ON t.category_id = c.id
       WHERE t.user_id = ? AND t.type = 'expense' AND DATE_FORMAT(t.date, '%Y-%m') = ?
       GROUP BY t.category_id, c.name, c.color`,
      [req.userId, targetMonth]
    );

    const [totals] = await db.query(
      `SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) as total_income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as total_expense
       FROM transactions
       WHERE user_id = ? AND DATE_FORMAT(date, '%Y-%m') = ?`,
      [req.userId, targetMonth]
    );

    const report = budgetRows.map(b => {
      const spent = spentRows.find(s => s.category_id === b.category_id);
      const value = spent ? Number(spent.spent) : 0;
      return {
        category_id: b.category_id,
        category_name: b.category_name,
        category_color: b.category_color,
        budgeted: Number(b.amount),
        spent: value,
        remaining: Number(b.amount) - value,
        percent: b.amount > 0 ? Math.min(100, (value / b.amount) * 100).toFixed(2) : 0,
      };
    });

    res.json({
      month: targetMonth,
      total_income: Number(totals[0].total_income),
      total_expense: Number(totals[0].total_expense),
      categories: report,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
