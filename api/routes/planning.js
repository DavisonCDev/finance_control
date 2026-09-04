// Planejamento mensal (spec §8).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const month = req.query.month || dates.toIsoDate(new Date()).slice(0, 7);
  const [plans] = await db.query(
    'SELECT * FROM monthly_plans WHERE user_id = ? AND reference_month = ?',
    [req.userId, month]
  );
  const plan = plans[0] || null;
  if (!plan) return res.json({ month, plan: null, items: [] });
  const [items] = await db.query(
    `SELECT i.*, c.name AS category_name
     FROM monthly_plan_items i
     LEFT JOIN categories c ON c.id = i.category_id
     WHERE i.plan_id = ?`,
    [plan.id]
  );
  res.json({ month, plan, items });
}));

router.post('/', asyncHandler(async (req, res) => {
  const { reference_month, note } = req.body;
  const [existing] = await db.query('SELECT id FROM monthly_plans WHERE user_id = ? AND reference_month = ?', [req.userId, reference_month]);
  let id;
  if (existing.length) {
    id = existing[0].id;
    await db.query('UPDATE monthly_plans SET note = ? WHERE id = ?', [note || null, id]);
  } else {
    const [result] = await db.query('INSERT INTO monthly_plans (user_id, reference_month, note) VALUES (?, ?, ?)', [req.userId, reference_month, note || null]);
    id = result.insertId;
  }
  res.json({ id, message: 'Planejamento salvo.' });
}));

router.post('/:id/items', asyncHandler(async (req, res) => {
  const { category_id, type, amount, notes } = req.body;
  const [result] = await db.query(
    'INSERT INTO monthly_plan_items (plan_id, category_id, type, amount, notes) VALUES (?, ?, ?, ?, ?)',
    [req.params.id, category_id || null, type || 'limit', amount, notes || null]
  );
  res.status(201).json({ id: result.insertId });
}));

router.delete('/items/:itemId', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM monthly_plan_items WHERE id = ?', [req.params.itemId]);
  res.json({ message: 'Item removido.' });
}));

module.exports = router;
