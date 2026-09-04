// Open Finance e conexões bancárias (spec §28).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

router.get('/connections', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM bank_connections WHERE user_id = ?', [req.userId]);
  res.json({ connections: rows });
}));

router.get('/accounts', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM bank_account_links WHERE user_id = ?', [req.userId]);
  res.json({ accounts: rows });
}));

router.post('/connect', asyncHandler(async (req, res) => {
  res.status(501).json({ message: 'Conector Open Finance não configurado. Defina OPEN_FINANCE_PROVIDER e credenciais no .env.' });
}));

router.delete('/connections/:id', asyncHandler(async (req, res) => {
  await db.query('DELETE FROM bank_connections WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Conexão removida.' });
}));

module.exports = router;
