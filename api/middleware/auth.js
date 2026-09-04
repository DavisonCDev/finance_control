const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const db = require('../db');

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Valida o JWT e a sessão correspondente. Sessões revogadas param de funcionar
 * imediatamente, o que permite encerramento remoto de dispositivos (spec §1, §15).
 */
async function authenticate(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) return res.status(401).json({ error: 'Token não fornecido.' });

  let decoded;
  try {
    decoded = jwt.verify(token, process.env.JWT_SECRET);
  } catch {
    return res.status(401).json({ error: 'Token inválido ou expirado.' });
  }

  try {
    const [sessions] = await db.query(
      'SELECT id, revoked_at FROM user_sessions WHERE token_hash = ?',
      [hashToken(token)]
    );

    // Sessões só passam a existir a partir desta versão; tokens antigos seguem
    // válidos até expirar, mas qualquer sessão registrada e revogada é bloqueada.
    if (sessions.length > 0) {
      if (sessions[0].revoked_at) return res.status(401).json({ error: 'Sessão encerrada.' });
      await db.query('UPDATE user_sessions SET last_seen_at = NOW() WHERE id = ?', [sessions[0].id]);
      req.sessionId = sessions[0].id;
    }

    const [users] = await db.query(
      `SELECT id, name, email, currency, language, timezone, first_day_of_month, date_format,
              theme, privacy_mode, hide_values, plan, is_admin, two_factor_enabled,
              biometric_enabled, auto_lock_minutes, pin_hash IS NOT NULL AS has_pin, deleted_at
       FROM users WHERE id = ?`,
      [decoded.id]
    );
    if (users.length === 0 || users[0].deleted_at) {
      return res.status(401).json({ error: 'Usuário inválido.' });
    }

    req.userId = users[0].id;
    req.user = users[0];
    req.token = token;
    next();
  } catch (err) {
    next(err);
  }
}

function requireAdmin(req, res, next) {
  if (!req.user?.is_admin) return res.status(403).json({ error: 'Acesso restrito a administradores.' });
  next();
}

// Bloqueia recursos exclusivos de planos pagos (spec §47).
const PLAN_FEATURES = {
  free: ['accounts', 'categories', 'transactions', 'basic_reports', 'budgets'],
  premium: [
    'accounts', 'categories', 'transactions', 'basic_reports', 'advanced_reports', 'budgets',
    'goals', 'investments', 'debts', 'assets', 'ai', 'ocr', 'export', 'open_finance', 'unlimited_cards',
  ],
  family_premium: [
    'accounts', 'categories', 'transactions', 'basic_reports', 'advanced_reports', 'budgets',
    'goals', 'investments', 'debts', 'assets', 'ai', 'ocr', 'export', 'open_finance', 'unlimited_cards',
    'family', 'advanced_permissions', 'family_dashboard',
  ],
};

function requireFeature(feature) {
  return (req, res, next) => {
    const plan = req.user?.plan || 'free';
    if (req.user?.is_admin || PLAN_FEATURES[plan]?.includes(feature)) return next();
    res.status(402).json({
      error: 'Recurso disponível nos planos Premium.',
      feature,
      current_plan: plan,
    });
  };
}

module.exports = authenticate;
module.exports.authenticate = authenticate;
module.exports.requireAdmin = requireAdmin;
module.exports.requireFeature = requireFeature;
module.exports.hashToken = hashToken;
module.exports.PLAN_FEATURES = PLAN_FEATURES;
