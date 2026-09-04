// Insights e recomendações (spec §22, §46).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  const [rows] = await db.query(
    'SELECT * FROM insights WHERE user_id = ? AND dismissed_at IS NULL ORDER BY created_at DESC LIMIT ?',
    [req.userId, limit]
  );
  res.json({ insights: rows });
}));

router.put('/:id/dismiss', asyncHandler(async (req, res) => {
  await db.query('UPDATE insights SET dismissed_at = NOW() WHERE id = ? AND user_id = ?', [req.params.id, req.userId]);
  res.json({ message: 'Insight descartado.' });
}));

module.exports = router;
