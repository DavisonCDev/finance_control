const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    'SELECT * FROM cost_centers WHERE (user_id = ? OR user_id IS NULL) AND active = TRUE ORDER BY sort_order, name',
    [req.userId]
  );
  res.json(rows);
}));

router.post('/', asyncHandler(async (req, res) => {
  const { name } = req.body || {};
  if (!name) {
    const error = new Error('Nome do centro de custo é obrigatório.');
    error.status = 400;
    throw error;
  }
  const [result] = await db.query(
    'INSERT INTO cost_centers (user_id, name) VALUES (?, ?)',
    [req.userId, name]
  );
  const [rows] = await db.query('SELECT * FROM cost_centers WHERE id = ?', [result.insertId]);
  res.status(201).json(rows[0]);
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const { name, active } = req.body || {};
  await db.query(
    'UPDATE cost_centers SET name = ?, active = ? WHERE id = ? AND user_id = ?',
    [name, active !== undefined ? active : true, req.params.id, req.userId]
  );
  const [rows] = await db.query('SELECT * FROM cost_centers WHERE id = ?', [req.params.id]);
  res.json(rows[0]);
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM cost_centers WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Centro de custo removido.' });
}));

module.exports = router;
