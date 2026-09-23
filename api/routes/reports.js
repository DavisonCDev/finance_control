const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const {
  getDRE,
  getYearlyCashFlow,
  getYearlyDRE,
  getDREDetailed,
  getMonthlyGoals,
  upsertMonthlyGoals,
} = require('../services/financialReports');

const router = express.Router();
router.use(authenticate);

router.get('/monthly', asyncHandler(async (req, res) => {
  const { month, cost_center_id } = req.query;
  const targetMonth = month || new Date().toISOString().slice(0, 7);

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
     WHERE t.user_id = ? AND t.type = 'expense' AND t.deleted_at IS NULL AND DATE_FORMAT(t.accrual_date, '%Y-%m') = ?
     GROUP BY t.category_id, c.name, c.color`,
    [req.userId, targetMonth]
  );

  const [totals] = await db.query(
    `SELECT
      COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) as total_income,
      COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) as total_expense
     FROM transactions
     WHERE user_id = ? AND deleted_at IS NULL AND DATE_FORMAT(accrual_date, '%Y-%m') = ?`,
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
}));

router.get('/dre', asyncHandler(async (req, res) => {
  const { month, cost_center_id } = req.query;
  const data = await getDRE(
    req.userId,
    month || new Date().toISOString().slice(0, 7),
    { costCenterId: cost_center_id }
  );
  res.json(data);
}));

// ============================================================
// ANUAL: FC, DRE, DRE Detalhado, Metas
// ============================================================

router.get('/cashflow-yearly', asyncHandler(async (req, res) => {
  const y = Number(req.query.year || new Date().getFullYear());
  res.json(await getYearlyCashFlow(req.userId, y));
}));

router.get('/dre-yearly', asyncHandler(async (req, res) => {
  const y = Number(req.query.year || new Date().getFullYear());
  res.json(await getYearlyDRE(req.userId, y));
}));

router.get('/dre-detailed', asyncHandler(async (req, res) => {
  const y = Number(req.query.year || new Date().getFullYear());
  const { pc_group, parent_code } = req.query;
  res.json(await getDREDetailed(req.userId, y, pc_group || null, parent_code || null));
}));

router.get('/goals-yearly', asyncHandler(async (req, res) => {
  const y = Number(req.query.year || new Date().getFullYear());
  res.json(await getMonthlyGoals(req.userId, y));
}));

router.put('/goals-yearly', asyncHandler(async (req, res) => {
  const y = Number(req.body.year || new Date().getFullYear());
  const { goal_type, months } = req.body;
  if (!goal_type || !Array.isArray(months) || months.length !== 12) {
    return res.status(400).json({ error: 'goal_type and months[12] required' });
  }
  res.json(await upsertMonthlyGoals(req.userId, y, goal_type, months));
}));

module.exports = router;
