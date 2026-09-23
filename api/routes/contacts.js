const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    'SELECT * FROM contacts WHERE (user_id = ? OR user_id IS NULL) AND active = TRUE ORDER BY name',
    [req.userId]
  );
  res.json(rows);
}));

router.post('/', asyncHandler(async (req, res) => {
  const { name, type } = req.body || {};
  if (!name) {
    const error = new Error('Nome do contato é obrigatório.');
    error.status = 400;
    throw error;
  }
  const [result] = await db.query(
    'INSERT INTO contacts (user_id, name, type) VALUES (?, ?, ?)',
    [req.userId, name, type || 'other']
  );
  const [rows] = await db.query('SELECT * FROM contacts WHERE id = ?', [result.insertId]);
  res.status(201).json(rows[0]);
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const { name, type, active } = req.body || {};
  await db.query(
    'UPDATE contacts SET name = ?, type = ?, active = ? WHERE id = ? AND user_id = ?',
    [name, type, active !== undefined ? active : true, req.params.id, req.userId]
  );
  const [rows] = await db.query('SELECT * FROM contacts WHERE id = ?', [req.params.id]);
  res.json(rows[0]);
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM contacts WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Contato removido.' });
}));

module.exports = router;
