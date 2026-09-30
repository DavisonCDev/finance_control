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
    // Uma unica query traz usuario + sessao (LEFT JOIN no token_hash):
    // com banco remoto, cada query sequencial custa um round-trip inteiro.
    const [rows] = await db.query(
      `SELECT u.id, u.name, u.email, u.currency, u.language, u.timezone, u.first_day_of_month, u.date_format,
              u.theme, u.privacy_mode, u.hide_values, u.plan, u.is_admin, u.two_factor_enabled,
              u.biometric_enabled, u.auto_lock_minutes, u.pin_hash IS NOT NULL AS has_pin, u.deleted_at,
              s.id AS session_id, s.revoked_at
       FROM users u
       LEFT JOIN user_sessions s ON s.token_hash = ?
       WHERE u.id = ?`,
      [hashToken(token), decoded.id]
    );

    if (rows.length === 0 || rows[0].deleted_at) {
      return res.status(401).json({ error: 'Usuário inválido.' });
    }

    const { session_id: sessionId, revoked_at: revokedAt, ...user } = rows[0];

    // Sessões só passam a existir a partir desta versão; tokens antigos seguem
    // válidos até expirar, mas qualquer sessão registrada e revogada é bloqueada.
    if (sessionId) {
      if (revokedAt) return res.status(401).json({ error: 'Sessão encerrada.' });
      req.sessionId = sessionId;
      // Telemetria: last_seen em background, sem custo na resposta.
      db.query('UPDATE user_sessions SET last_seen_at = NOW() WHERE id = ?', [sessionId])
        .catch(err => console.error('last_seen:', err.message));
    }

    req.userId = user.id;
    req.user = user;
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
