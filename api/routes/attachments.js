// Anexos e comprovantes (spec §9).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    'SELECT * FROM attachments WHERE user_id = ? ORDER BY created_at DESC',
    [req.userId]
  );
  res.json({ attachments: rows });
}));

router.post('/', asyncHandler(async (req, res) => {
  const { transaction_id, file_name, file_url, file_size, mime_type } = req.body;
  const [result] = await db.query(
    'INSERT INTO attachments (user_id, transaction_id, file_name, file_url, file_size, mime_type) VALUES (?, ?, ?, ?, ?, ?)',
    [req.userId, transaction_id || null, file_name, file_url, file_size || 0, mime_type || null]
  );
  res.status(201).json({ id: result.insertId, message: 'Anexo registrado.' });
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM attachments WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Anexo removido.' });
}));

module.exports = router;
