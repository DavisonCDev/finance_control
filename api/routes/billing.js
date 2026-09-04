// Planos e cobrança (spec §50).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

router.get('/plan', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM plans ORDER BY price ASC');
  res.json({ current: req.user.plan, plans: rows });
}));

router.get('/subscriptions', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM subscriptions WHERE user_id = ? ORDER BY created_at DESC', [req.userId]);
  res.json({ subscriptions: rows });
}));

router.post('/subscribe', asyncHandler(async (req, res) => {
  const { plan_code } = req.body;
  const [plans] = await db.query('SELECT * FROM plans WHERE code = ?', [plan_code]);
  if (plans.length === 0) throw Object.assign(new Error('Plano não encontrado.'), { status: 404 });
  const [result] = await db.query(
    'INSERT INTO subscriptions (user_id, plan_code, status, billing_cycle, start_date) VALUES (?, ?, ?, ?, CURDATE())',
    [req.userId, plan_code, 'active', 'monthly']
  );
  await db.query('UPDATE users SET plan = ? WHERE id = ?', [plan_code, req.userId]);
  res.status(201).json({ id: result.insertId, message: 'Assinatura ativada.' });
}));

module.exports = router;
