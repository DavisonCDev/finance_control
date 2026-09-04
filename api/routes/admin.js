// Administração do sistema (spec §49, §50).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();

router.use(authenticate);
router.use((req, res, next) => {
  if (!req.user.is_admin) throw Object.assign(new Error('Acesso restrito a administradores.'), { status: 403 });
  next();
});

router.get('/users', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT id, name, email, plan, is_admin, created_at, last_login_at, deleted_at FROM users ORDER BY id DESC LIMIT 200');
  res.json({ users: rows });
}));

router.get('/metrics', asyncHandler(async (req, res) => {
  const [users] = await db.query('SELECT COUNT(*) AS c FROM users');
  const [transactions] = await db.query("SELECT COUNT(*) AS c FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense')");
  const [families] = await db.query('SELECT COUNT(*) AS c FROM families');
  res.json({ users: users[0].c, transactions: transactions[0].c, families: families[0].c });
}));

router.get('/support-tickets', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM support_tickets ORDER BY created_at DESC LIMIT 100');
  res.json({ tickets: rows });
}));

module.exports = router;
