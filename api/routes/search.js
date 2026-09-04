// Busca global (spec §24).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const scope = require('../lib/scope');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const q = (req.query.q || '').trim();
  if (!q || q.length < 2) throw Object.assign(new Error('Informe pelo menos 2 caracteres.'), { status: 400 });
  const visibility = await scope.visibilityClause(req.userId, 't');
  const [transactions] = await db.query(
    `SELECT t.* FROM transactions t
     WHERE t.deleted_at IS NULL AND ${visibility.sql} AND (t.description LIKE ? OR t.notes LIKE ?)
     ORDER BY t.date DESC LIMIT 100`,
    [...visibility.params, `%${q}%`, `%${q}%`]
  );
  res.json({ query: q, results: transactions });
}));

module.exports = router;
