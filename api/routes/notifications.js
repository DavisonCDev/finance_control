// Central de notificações e alertas (spec §14).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { notify } = require('../lib/notify');
const jobs = require('../lib/jobs');

const router = express.Router();
router.use(authenticate);

const TYPES = [
  'budget_near', 'budget_over', 'bill_due', 'card_due', 'invoice_closed', 'low_balance',
  'installment_due', 'income_missing', 'family_expense', 'family_budget', 'family_event',
  'goal', 'insight', 'system',
];
const SEVERITIES = ['info', 'warning', 'critical'];

// Notificação agendada para o futuro ainda não deve aparecer na lista.
const VISIBLE = '(scheduled_at IS NULL OR scheduled_at <= NOW())';

async function unreadCount(userId) {
  const [[row]] = await db.query(
    `SELECT COUNT(*) AS total FROM notifications
     WHERE user_id = ? AND read_at IS NULL AND ${VISIBLE}`,
    [userId]
  );
  return Number(row.total);
}

router.get('/', asyncHandler(async (req, res) => {
  const params = [req.userId];
  let sql = `SELECT * FROM notifications WHERE user_id = ? AND ${VISIBLE}`;

  if (req.query.unread === 'true') sql += ' AND read_at IS NULL';
  if (req.query.type) {
    sql += ' AND type = ?';
    params.push(req.query.type);
  }
  if (req.query.severity) {
    sql += ' AND severity = ?';
    params.push(req.query.severity);
  }

  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
  sql += ` ORDER BY created_at DESC LIMIT ${limit}`;

  const [notifications] = await db.query(sql, params);
  res.json({ notifications, unread_count: await unreadCount(req.userId) });
}));

router.get('/unread-count', asyncHandler(async (req, res) => {
  res.json({ unread_count: await unreadCount(req.userId) });
}));

// Rotas com caminho fixo antes das paramétricas para não colidirem com /:id.
router.put('/read-all', asyncHandler(async (req, res) => {
  const [result] = await db.query(
    'UPDATE notifications SET read_at = NOW() WHERE user_id = ? AND read_at IS NULL',
    [req.userId]
  );
  res.json({ message: 'Notificações marcadas como lidas.', updated: result.affectedRows });
}));

router.put('/:id/read', asyncHandler(async (req, res) => {
  const [result] = await db.query(
    'UPDATE notifications SET read_at = NOW() WHERE id = ? AND user_id = ?',
    [req.params.id, req.userId]
  );
  if (result.affectedRows === 0) {
    throw Object.assign(new Error('Notificação não encontrada.'), { status: 404 });
  }
  const [rows] = await db.query('SELECT * FROM notifications WHERE id = ?', [req.params.id]);
  res.json(rows[0]);
}));

router.post('/', asyncHandler(async (req, res) => {
  const { title, message, type = 'system', severity = 'info', scheduled_at = null } = req.body;

  if (!title || !message) throw Object.assign(new Error('Título e mensagem são obrigatórios.'), { status: 400 });
  if (!TYPES.includes(type)) throw Object.assign(new Error('Tipo de notificação inválido.'), { status: 400 });
  if (!SEVERITIES.includes(severity)) throw Object.assign(new Error('Severidade inválida.'), { status: 400 });

  const id = await notify({
    userId: req.userId,
    type,
    title,
    message,
    severity,
    scheduledAt: scheduled_at || null,
  });

  if (!id) {
    // notify() devolve null quando a preferência está desativada ou é duplicata.
    return res.status(202).json({ message: 'Notificação suprimida pelas preferências do usuário.' });
  }

  const [rows] = await db.query('SELECT * FROM notifications WHERE id = ?', [id]);
  res.status(201).json(rows[0]);
}));

router.post('/scan', asyncHandler(async (req, res) => {
  const result = await jobs.scanNotifications(req.userId);
  res.json({ message: 'Varredura de alertas concluída.', created: result });
}));

// DELETE / — limpa apenas as já lidas, preservando o que o usuário ainda não viu.
router.delete('/', asyncHandler(async (req, res) => {
  const [result] = await db.query(
    'DELETE FROM notifications WHERE user_id = ? AND read_at IS NOT NULL',
    [req.userId]
  );
  res.json({ message: 'Notificações lidas removidas.', deleted: result.affectedRows });
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  const [result] = await db.query(
    'DELETE FROM notifications WHERE id = ? AND user_id = ?',
    [req.params.id, req.userId]
  );
  if (result.affectedRows === 0) {
    throw Object.assign(new Error('Notificação não encontrada.'), { status: 404 });
  }
  res.json({ message: 'Notificação removida.' });
}));

module.exports = router;
