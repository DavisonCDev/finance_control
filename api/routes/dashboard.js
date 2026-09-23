// Dashboard consolidado (regime de caixa vs competencia).
const express = require('express');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { getDashboard } = require('../services/financialReports');
const jobs = require('../lib/jobs');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const { month } = req.query;
  const targetMonth = month || new Date().toISOString().slice(0, 7);

  const dash = await getDashboard(req.userId, targetMonth);
  const net = await jobs.netWorthTotals(req.userId);

  res.json({ ...dash, net_worth: net.net_worth });
}));

module.exports = router;
