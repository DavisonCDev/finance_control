// Automações agendadas (spec §35).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

const TYPES = ['recurring_generate','goal_contribution','invoice_close','notification_scan','net_worth_snapshot','backup','report'];
const FREQUENCIES = ['daily','weekly','monthly'];

router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM automations WHERE user_id = ? ORDER BY active DESC, next_run_at ASC', [req.userId]);
  res.json({ automations: rows });
}));

router.post('/', asyncHandler(async (req, res) => {
  const { name, type, frequency, day_of_month, next_run_at, config } = req.body;
  if (!name || !type || !frequency) throw Object.assign(new Error('name, type e frequency são obrigatórios.'), { status: 400 });
  if (!TYPES.includes(type) || !FREQUENCIES.includes(frequency)) throw Object.assign(new Error('Tipo ou frequência inválida.'), { status: 400 });
  const [result] = await db.query(
    'INSERT INTO automations (user_id, name, type, frequency, day_of_month, next_run_at, config) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [req.userId, name, type, frequency, day_of_month || null, next_run_at || null, config ? JSON.stringify(config) : null]
  );
  res.status(201).json({ id: result.insertId });
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const b = req.body;
  const fields = ['name','type','frequency','day_of_month','next_run_at','config','active'];
  const updates = []; const values = [];
  for (const f of fields) { if (b[f] !== undefined) { updates.push(`${f} = ?`); values.push(f === 'config' && typeof b[f] === 'object' ? JSON.stringify(b[f]) : b[f]); } }
  if (updates.length === 0) return res.json({});
  values.push(req.params.id, req.userId);
  await db.query(`UPDATE automations SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`, values);
  res.json({ id: req.params.id, message: 'Automação atualizada.' });
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM automations WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Automação removida.' });
}));

module.exports = router;
