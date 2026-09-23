// Fluxo de Caixa: regime de caixa (payment_date + is_paid).
const express = require('express');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { getCashFlow } = require('../services/financialReports');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const { month, bank_account_id, cost_center_id } = req.query;
  const data = await getCashFlow(
    req.userId,
    month || new Date().toISOString().slice(0, 7),
    { bankAccountId: bank_account_id, costCenterId: cost_center_id }
  );
  res.json(data);
}));

module.exports = router;
