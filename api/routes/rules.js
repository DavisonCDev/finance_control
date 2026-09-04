// Regras automáticas (spec §21).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

const MATCH_FIELDS = ['description','amount','account','card','type','category'];
const OPERATORS = ['contains','not_contains','equals','starts_with','ends_with','greater_than','less_than','regex'];
const ACTIONS = ['set_category','add_tag','set_account','set_card','require_confirmation','link_invoice','mark_transfer','set_description'];

router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM auto_rules WHERE user_id = ? ORDER BY priority DESC, id DESC', [req.userId]);
  res.json({ rules: rows });
}));

router.post('/', asyncHandler(async (req, res) => {
  const { name, priority = 0, match_field, match_operator, match_value, action_type, action_value, stop_processing } = req.body;
  if (!name || !match_field || !match_value || !action_type) throw Object.assign(new Error('Campos obrigatórios: name, match_field, match_value, action_type.'), { status: 400 });
  if (!MATCH_FIELDS.includes(match_field) || !OPERATORS.includes(match_operator) || !ACTIONS.includes(action_type)) {
    throw Object.assign(new Error('Valor de campo/operador/ação inválido.'), { status: 400 });
  }
  const [result] = await db.query(
    'INSERT INTO auto_rules (user_id, name, priority, match_field, match_operator, match_value, action_type, action_value, stop_processing) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [req.userId, name, priority, match_field, match_operator || 'contains', match_value, action_type, action_value || null, stop_processing || false]
  );
  res.status(201).json({ id: result.insertId });
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const b = req.body;
  const fields = ['name','priority','match_field','match_operator','match_value','action_type','action_value','stop_processing','active'];
  const updates = [];
  const values = [];
  for (const f of fields) { if (b[f] !== undefined) { updates.push(`${f} = ?`); values.push(b[f]); } }
  if (updates.length === 0) return res.json({});
  values.push(req.params.id, req.userId);
  await db.query(`UPDATE auto_rules SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`, values);
  res.json({ id: req.params.id, message: 'Regra atualizada.' });
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM auto_rules WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Regra removida.' });
}));

module.exports = router;
