// Sincronização offline e estados (spec §31).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

router.get('/state', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM sync_state WHERE user_id = ?', [req.userId]);
  res.json({ state: rows[0] || null });
}));

router.post('/state', asyncHandler(async (req, res) => {
  const { last_sync_at, device_id, pending_count } = req.body;
  await db.query(
    `INSERT INTO sync_state (user_id, last_sync_at, device_id, pending_count) VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE last_sync_at = VALUES(last_sync_at), device_id = VALUES(device_id), pending_count = VALUES(pending_count)`,
    [req.userId, last_sync_at || dates.toIsoDate(new Date()) + 'T00:00:00', device_id, pending_count || 0]
  );
  res.json({ message: 'Estado de sincronização atualizado.' });
}));

module.exports = router;
