// Perfil, preferências, privacidade, PIN e dispositivos do usuário (spec §1, §14, §15).
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');

const router = express.Router();
router.use(authenticate);

const THEMES = ['system', 'light', 'dark'];
const PUSH_PLATFORMS = ['android', 'ios', 'web', 'windows'];

function badRequest(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

function sanitizeUser(row) {
  if (!row) return null;
  const { password_hash, two_factor_secret, pin_hash, reset_token, email_verify_token, ...safe } = row;
  return { ...safe, has_pin: pin_hash != null };
}

async function loadUser(userId) {
  const [rows] = await db.query('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL', [userId]);
  if (!rows[0]) throw badRequest('Usuário não encontrado.', 404);
  return rows[0];
}

function toBool(value) {
  return value === true || value === 1 || value === '1' || value === 'true';
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const user = await loadUser(req.userId);

    const [subs] = await db.query(
      `SELECT * FROM subscriptions WHERE user_id = ? AND status = 'active'
       ORDER BY started_at DESC LIMIT 1`,
      [req.userId]
    );
    const subscription = subs[0] || null;

    // A tabela plans é opcional (catálogo comercial); sem ela devolvemos só o código.
    let planDetails = null;
    try {
      const [plans] = await db.query('SELECT * FROM plans WHERE code = ? LIMIT 1', [subscription?.plan_code || user.plan]);
      planDetails = plans[0] || null;
    } catch (err) {
      console.error('plans:', err.message);
    }

    const [[sessions]] = await db.query(
      'SELECT COUNT(*) AS total FROM user_sessions WHERE user_id = ? AND revoked_at IS NULL AND expires_at > NOW()',
      [req.userId]
    );

    res.json({
      user: sanitizeUser(user),
      plan: { code: subscription?.plan_code || user.plan, subscription, details: planDetails },
      active_sessions: sessions.total,
    });
  })
);

router.put(
  '/',
  asyncHandler(async (req, res) => {
    const current = await loadUser(req.userId);
    const fields = ['name', 'phone', 'photo_url', 'currency', 'country', 'language', 'timezone', 'first_day_of_month', 'date_format', 'theme'];

    const changes = {};
    for (const field of fields) {
      if (req.body[field] === undefined) continue;
      let value = req.body[field];

      if (field === 'theme' && !THEMES.includes(value)) {
        throw badRequest(`Tema inválido. Use: ${THEMES.join(', ')}.`);
      }
      if (field === 'first_day_of_month') {
        value = Number(value);
        if (!Number.isInteger(value) || value < 1 || value > 28) {
          throw badRequest('O primeiro dia do mês deve estar entre 1 e 28.');
        }
      }
      if (field === 'name' && !String(value).trim()) throw badRequest('Nome não pode ficar vazio.');

      if (String(current[field] ?? '') !== String(value ?? '')) changes[field] = value;
    }

    if (Object.keys(changes).length === 0) {
      return res.json({ user: sanitizeUser(current), message: 'Nada a atualizar.' });
    }

    const sets = Object.keys(changes).map((field) => `${field} = ?`).join(', ');
    await db.query(`UPDATE users SET ${sets} WHERE id = ?`, [...Object.values(changes), req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', changes);

    res.json({ user: sanitizeUser(await loadUser(req.userId)) });
  })
);

router.put(
  '/privacy',
  asyncHandler(async (req, res) => {
    const current = await loadUser(req.userId);
    const privacyMode = req.body.privacy_mode === undefined ? current.privacy_mode : toBool(req.body.privacy_mode);
    const hideValues = req.body.hide_values === undefined ? current.hide_values : toBool(req.body.hide_values);

    await db.query('UPDATE users SET privacy_mode = ?, hide_values = ? WHERE id = ?', [privacyMode, hideValues, req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', { privacy_mode: privacyMode, hide_values: hideValues });

    res.json({ privacy_mode: !!privacyMode, hide_values: !!hideValues });
  })
);

router.put(
  '/security',
  asyncHandler(async (req, res) => {
    const current = await loadUser(req.userId);
    const biometric = req.body.biometric_enabled === undefined ? current.biometric_enabled : toBool(req.body.biometric_enabled);

    let autoLock = current.auto_lock_minutes;
    if (req.body.auto_lock_minutes !== undefined) {
      autoLock = Number(req.body.auto_lock_minutes);
      if (!Number.isInteger(autoLock) || autoLock < 0 || autoLock > 120) {
        throw badRequest('O bloqueio automático deve estar entre 0 e 120 minutos.');
      }
    }

    await db.query('UPDATE users SET biometric_enabled = ?, auto_lock_minutes = ? WHERE id = ?', [biometric, autoLock, req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', { biometric_enabled: biometric, auto_lock_minutes: autoLock });

    res.json({ biometric_enabled: !!biometric, auto_lock_minutes: autoLock });
  })
);

router.post(
  '/pin',
  asyncHandler(async (req, res) => {
    const { pin } = req.body;
    if (!/^\d{4,8}$/.test(String(pin || ''))) throw badRequest('O PIN deve ter de 4 a 8 dígitos numéricos.');

    await db.query('UPDATE users SET pin_hash = ? WHERE id = ?', [await bcrypt.hash(String(pin), 10), req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', { pin: 'definido' });

    res.json({ message: 'PIN definido.' });
  })
);

router.post(
  '/pin/verify',
  asyncHandler(async (req, res) => {
    const { pin } = req.body;
    const user = await loadUser(req.userId);
    if (!user.pin_hash || !pin) return res.json({ valid: false });

    res.json({ valid: await bcrypt.compare(String(pin), user.pin_hash) });
  })
);

router.delete(
  '/pin',
  asyncHandler(async (req, res) => {
    const { password } = req.body;
    if (!password) throw badRequest('Senha é obrigatória.');

    const user = await loadUser(req.userId);
    if (!(await bcrypt.compare(String(password), user.password_hash || ''))) throw badRequest('Senha incorreta.', 401);

    await db.query('UPDATE users SET pin_hash = NULL WHERE id = ?', [req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', { pin: 'removido' });

    res.json({ message: 'PIN removido.' });
  })
);

router.get(
  '/notification-preferences',
  asyncHandler(async (req, res) => {
    const [rows] = await db.query('SELECT * FROM notification_preferences WHERE user_id = ? ORDER BY type', [req.userId]);
    res.json(rows);
  })
);

router.put(
  '/notification-preferences',
  asyncHandler(async (req, res) => {
    const { preferences } = req.body;
    if (!Array.isArray(preferences) || preferences.length === 0) {
      throw badRequest('Envie um array em "preferences".');
    }

    for (const pref of preferences) {
      if (!pref?.type) throw badRequest('Cada preferência precisa do campo "type".');
      await db.query(
        `INSERT INTO notification_preferences
           (user_id, type, enabled, channel_push, channel_email, channel_inapp, quiet_hours_start, quiet_hours_end)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           enabled = VALUES(enabled), channel_push = VALUES(channel_push), channel_email = VALUES(channel_email),
           channel_inapp = VALUES(channel_inapp), quiet_hours_start = VALUES(quiet_hours_start),
           quiet_hours_end = VALUES(quiet_hours_end)`,
        [
          req.userId,
          pref.type,
          pref.enabled === undefined ? true : toBool(pref.enabled),
          pref.channel_push === undefined ? true : toBool(pref.channel_push),
          pref.channel_email === undefined ? false : toBool(pref.channel_email),
          pref.channel_inapp === undefined ? true : toBool(pref.channel_inapp),
          pref.quiet_hours_start || null,
          pref.quiet_hours_end || null,
        ]
      );
    }

    const [rows] = await db.query('SELECT * FROM notification_preferences WHERE user_id = ? ORDER BY type', [req.userId]);
    res.json(rows);
  })
);

router.post(
  '/push-tokens',
  asyncHandler(async (req, res) => {
    const { token, platform } = req.body;
    if (!token) throw badRequest('Token é obrigatório.');
    if (!PUSH_PLATFORMS.includes(platform)) throw badRequest(`Plataforma inválida. Use: ${PUSH_PLATFORMS.join(', ')}.`);

    // O mesmo aparelho pode trocar de usuário: garantimos o vínculo mais recente.
    await db.query('INSERT IGNORE INTO push_tokens (user_id, token, platform) VALUES (?, ?, ?)', [req.userId, token, platform]);
    await db.query('UPDATE push_tokens SET user_id = ?, platform = ? WHERE token = ?', [req.userId, platform, token]);

    res.status(201).json({ message: 'Dispositivo registrado para notificações.' });
  })
);

router.delete(
  '/push-tokens/:token',
  asyncHandler(async (req, res) => {
    await db.query('DELETE FROM push_tokens WHERE token = ? AND user_id = ?', [req.params.token, req.userId]);
    res.json({ message: 'Dispositivo removido.' });
  })
);

router.get(
  '/access-logs',
  asyncHandler(async (req, res) => {
    const [rows] = await db.query(
      'SELECT id, action, ip_address, user_agent, success, created_at FROM access_logs WHERE user_id = ? ORDER BY created_at DESC LIMIT 100',
      [req.userId]
    );
    res.json(rows);
  })
);

module.exports = router;
