// Autenticação, sessões, 2FA, recuperação de senha e exportação de dados (spec §1, §15).
const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const qrcode = require('qrcode');
const otplib = require('otplib');
const rateLimit = require('express-rate-limit');
const { OAuth2Client } = require('google-auth-library');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { hashToken } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit, logAccess, clientIp } = require('../lib/audit');
const { ensureDefaultPreferences } = require('../lib/notify');
const { sendVerificationEmail, sendPasswordResetEmail } = require('../lib/mailer');

const router = express.Router();

const SESSION_DAYS = 7;
const TOTP_ISSUER = 'Finance Control';

// Freia ataques de força bruta e enumeração de e-mails (spec §15).
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Muitas tentativas. Tente novamente em alguns minutos.' },
});

function badRequest(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

function sanitizeUser(row) {
  if (!row) return null;
  const { password_hash, two_factor_secret, pin_hash, reset_token, email_verify_token, ...safe } = row;
  return { ...safe, has_pin: pin_hash != null };
}

function isValidEmail(email) {
  return typeof email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim());
}

// otplib 13 substituiu a API `authenticator.*` por funções; o fallback mantém
// compatibilidade caso o projeto volte para a linha 12.x.
function generateTotpSecret() {
  return otplib.generateSecret ? otplib.generateSecret() : otplib.authenticator.generateSecret();
}

function totpUri(email, secret) {
  if (otplib.generateURI) return otplib.generateURI({ issuer: TOTP_ISSUER, label: email, secret });
  return otplib.authenticator.keyuri(email, TOTP_ISSUER, secret);
}

async function checkTotp(code, secret) {
  if (!code || !secret) return false;
  const token = String(code).replace(/\s/g, '');
  if (otplib.verify) {
    const result = await otplib.verify({ secret, token });
    return !!result?.valid;
  }
  return otplib.authenticator.check(token, secret);
}

async function issueSession(user, req) {
  const token = jwt.sign({ id: user.id, email: user.email }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || `${SESSION_DAYS}d`,
  });

  await db.query(
    `INSERT INTO user_sessions (user_id, token_hash, device_name, platform, ip_address, user_agent, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY))`,
    [
      user.id,
      hashToken(token),
      req.body?.device_name || null,
      req.body?.platform || null,
      clientIp(req),
      String(req.headers['user-agent'] || '').slice(0, 255) || null,
      SESSION_DAYS,
    ]
  );

  return token;
}

async function findUserById(id) {
  const [rows] = await db.query('SELECT * FROM users WHERE id = ? AND deleted_at IS NULL', [id]);
  return rows[0] || null;
}

async function findUserByEmail(email) {
  const [rows] = await db.query('SELECT * FROM users WHERE email = ? AND deleted_at IS NULL', [String(email).trim()]);
  return rows[0] || null;
}

// Cria as estruturas auxiliares que todo usuário novo precisa ter.
async function provisionNewUser(conn, userId) {
  await conn.query('INSERT IGNORE INTO user_streaks (user_id) VALUES (?)', [userId]);
  await conn.query(
    `INSERT INTO subscriptions (user_id, plan_code, status, started_at) VALUES (?, 'free', 'active', NOW())`,
    [userId]
  );
}

async function revokeOtherSessions(userId, keepSessionId = null) {
  await db.query(
    `UPDATE user_sessions SET revoked_at = NOW()
     WHERE user_id = ? AND revoked_at IS NULL AND (? IS NULL OR id <> ?)`,
    [userId, keepSessionId, keepSessionId]
  );
}

/**
 * Login social: vincula o provedor a uma conta existente pelo e-mail ou cria
 * uma nova. A senha local recebe um valor aleatório porque o acesso passa a ser
 * feito pelo provedor.
 */
async function loginWithProvider({ provider, providerId, email, name, photo }, req) {
  if (!email) throw badRequest('O provedor não retornou um e-mail válido.', 401);

  const existing = await findUserByEmail(email);
  if (existing) {
    await db.query(
      `UPDATE users SET provider = ?, provider_id = ?, email_verified = TRUE,
              photo_url = COALESCE(photo_url, ?), last_login_at = NOW()
       WHERE id = ?`,
      [provider, providerId, photo || null, existing.id]
    );
    const token = await issueSession(existing, req);
    await logAccess({ userId: existing.id, email: existing.email, action: 'login', req, success: true });
    return { user: sanitizeUser(await findUserById(existing.id)), token };
  }

  const randomHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 10);
  const userId = await withTransaction(async (conn) => {
    const [result] = await conn.query(
      `INSERT INTO users (name, email, password_hash, provider, provider_id, email_verified, photo_url, last_login_at)
       VALUES (?, ?, ?, ?, ?, TRUE, ?, NOW())`,
      [name || String(email).split('@')[0], String(email).trim(), randomHash, provider, providerId, photo || null]
    );
    await provisionNewUser(conn, result.insertId);
    return result.insertId;
  });

  await ensureDefaultPreferences(userId);
  const user = await findUserById(userId);
  const token = await issueSession(user, req);
  await logAccess({ userId, email: user.email, action: 'register', req, success: true });
  return { user: sanitizeUser(user), token };
}

router.post(
  '/register',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { name, email, password } = req.body;
    if (!name || !String(name).trim()) throw badRequest('Nome é obrigatório.');
    if (!isValidEmail(email)) throw badRequest('Informe um e-mail válido.');
    if (!password || String(password).length < 8) {
      throw badRequest('A senha deve ter no mínimo 8 caracteres.');
    }

    if (await findUserByEmail(email)) throw badRequest('E-mail já cadastrado.', 409);

    const passwordHash = await bcrypt.hash(String(password), 10);
    const verifyToken = crypto.randomBytes(24).toString('hex');

    const userId = await withTransaction(async (conn) => {
      const [result] = await conn.query(
        'INSERT INTO users (name, email, password_hash, email_verify_token) VALUES (?, ?, ?, ?)',
        [String(name).trim(), String(email).trim(), passwordHash, verifyToken]
      );
      await provisionNewUser(conn, result.insertId);
      return result.insertId;
    });

    await ensureDefaultPreferences(userId);

    const user = await findUserById(userId);
    const token = await issueSession(user, req);
    await sendVerificationEmail(user, verifyToken);
    await logAccess({ userId, email: user.email, action: 'register', req, success: true });

    res.status(201).json({ user: sanitizeUser(user), token });
  })
);

router.post(
  '/login',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) throw badRequest('E-mail e senha são obrigatórios.');

    const user = await findUserByEmail(email);
    const valid = user && (await bcrypt.compare(String(password), user.password_hash || ''));
    if (!valid) {
      await logAccess({ userId: user?.id || null, email: String(email).trim(), action: 'login_failed', req, success: false });
      throw badRequest('Credenciais inválidas.', 401);
    }

    // Com 2FA ativo a sessão só nasce depois do código TOTP.
    if (user.two_factor_enabled) {
      const challengeToken = jwt.sign({ id: user.id, purpose: '2fa' }, process.env.JWT_SECRET, { expiresIn: '5m' });
      return res.json({ two_factor_required: true, challenge_token: challengeToken });
    }

    await db.query('UPDATE users SET last_login_at = NOW() WHERE id = ?', [user.id]);
    const token = await issueSession(user, req);
    await logAccess({ userId: user.id, email: user.email, action: 'login', req, success: true });

    res.json({ user: sanitizeUser(await findUserById(user.id)), token });
  })
);

router.post(
  '/login/2fa',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { challenge_token, code } = req.body;
    if (!challenge_token || !code) throw badRequest('Token de desafio e código são obrigatórios.');

    let payload;
    try {
      payload = jwt.verify(challenge_token, process.env.JWT_SECRET);
    } catch {
      throw badRequest('Desafio inválido ou expirado.', 401);
    }
    if (payload.purpose !== '2fa') throw badRequest('Desafio inválido.', 401);

    const user = await findUserById(payload.id);
    if (!user || !user.two_factor_enabled) throw badRequest('Verificação em duas etapas indisponível.', 401);

    if (!(await checkTotp(code, user.two_factor_secret))) {
      await logAccess({ userId: user.id, email: user.email, action: '2fa_challenge', req, success: false });
      throw badRequest('Código inválido.', 401);
    }

    await db.query('UPDATE users SET last_login_at = NOW() WHERE id = ?', [user.id]);
    const token = await issueSession(user, req);
    await logAccess({ userId: user.id, email: user.email, action: '2fa_challenge', req, success: true });

    res.json({ user: sanitizeUser(await findUserById(user.id)), token });
  })
);

router.post(
  '/login/google',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { id_token } = req.body;
    if (!process.env.GOOGLE_CLIENT_ID) {
      throw badRequest('Login com Google não está configurado neste servidor (defina GOOGLE_CLIENT_ID).', 501);
    }
    if (!id_token) throw badRequest('id_token é obrigatório.');

    const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
    let payload;
    try {
      const ticket = await client.verifyIdToken({ idToken: id_token, audience: process.env.GOOGLE_CLIENT_ID });
      payload = ticket.getPayload();
    } catch {
      throw badRequest('Token do Google inválido.', 401);
    }

    const result = await loginWithProvider(
      { provider: 'google', providerId: payload.sub, email: payload.email, name: payload.name, photo: payload.picture },
      req
    );
    res.json(result);
  })
);

router.post(
  '/login/apple',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { identity_token } = req.body;
    if (!process.env.APPLE_CLIENT_ID) {
      throw badRequest('Login com Apple não está configurado neste servidor (defina APPLE_CLIENT_ID).', 501);
    }
    if (!identity_token) throw badRequest('identity_token é obrigatório.');

    // jose 6 é ESM puro: em CommonJS só carrega via import dinâmico.
    const { createRemoteJWKSet, jwtVerify } = await import('jose');
    const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

    let payload;
    try {
      const verified = await jwtVerify(identity_token, jwks, {
        issuer: 'https://appleid.apple.com',
        audience: process.env.APPLE_CLIENT_ID,
      });
      payload = verified.payload;
    } catch {
      throw badRequest('Token da Apple inválido.', 401);
    }

    const result = await loginWithProvider(
      { provider: 'apple', providerId: payload.sub, email: payload.email, name: req.body.name || null, photo: null },
      req
    );
    res.json(result);
  })
);

router.post(
  '/logout',
  authenticate,
  asyncHandler(async (req, res) => {
    if (req.sessionId) {
      await db.query('UPDATE user_sessions SET revoked_at = NOW() WHERE id = ? AND user_id = ?', [req.sessionId, req.userId]);
    } else if (req.token) {
      await db.query('UPDATE user_sessions SET revoked_at = NOW() WHERE token_hash = ? AND user_id = ?', [
        hashToken(req.token),
        req.userId,
      ]);
    }
    await logAccess({ userId: req.userId, email: req.user.email, action: 'logout', req, success: true });
    res.json({ message: 'Sessão encerrada.' });
  })
);

router.post(
  '/forgot-password',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { email } = req.body;
    const genericMessage = 'Se o e-mail estiver cadastrado, enviaremos as instruções de recuperação.';

    if (isValidEmail(email)) {
      const user = await findUserByEmail(email);
      if (user) {
        const token = crypto.randomBytes(24).toString('hex');
        await db.query(
          'UPDATE users SET reset_token = ?, reset_token_expires = DATE_ADD(NOW(), INTERVAL 1 HOUR) WHERE id = ?',
          [token, user.id]
        );
        await sendPasswordResetEmail(user, token);
      }
    }

    // Resposta sempre igual para não revelar quais e-mails existem.
    res.json({ message: genericMessage });
  })
);

router.post(
  '/reset-password',
  authLimiter,
  asyncHandler(async (req, res) => {
    const { token, password } = req.body;
    if (!token || !password) throw badRequest('Token e nova senha são obrigatórios.');
    if (String(password).length < 8) throw badRequest('A senha deve ter no mínimo 8 caracteres.');

    const [rows] = await db.query(
      'SELECT * FROM users WHERE reset_token = ? AND reset_token_expires > NOW() AND deleted_at IS NULL',
      [token]
    );
    const user = rows[0];
    if (!user) throw badRequest('Token inválido ou expirado.', 400);

    const passwordHash = await bcrypt.hash(String(password), 10);
    await db.query(
      'UPDATE users SET password_hash = ?, reset_token = NULL, reset_token_expires = NULL WHERE id = ?',
      [passwordHash, user.id]
    );
    await revokeOtherSessions(user.id);
    await logAccess({ userId: user.id, email: user.email, action: 'password_reset', req, success: true });

    res.json({ message: 'Senha redefinida. Faça login novamente.' });
  })
);

router.post(
  '/change-password',
  authenticate,
  asyncHandler(async (req, res) => {
    const { current_password, new_password } = req.body;
    if (!current_password || !new_password) throw badRequest('Senha atual e nova senha são obrigatórias.');
    if (String(new_password).length < 8) throw badRequest('A nova senha deve ter no mínimo 8 caracteres.');

    const user = await findUserById(req.userId);
    if (!(await bcrypt.compare(String(current_password), user.password_hash || ''))) {
      throw badRequest('Senha atual incorreta.', 401);
    }

    await db.query('UPDATE users SET password_hash = ? WHERE id = ?', [await bcrypt.hash(String(new_password), 10), user.id]);
    await revokeOtherSessions(user.id, req.sessionId || null);
    await logAccess({ userId: user.id, email: user.email, action: 'password_reset', req, success: true });

    res.json({ message: 'Senha alterada. Os outros dispositivos foram desconectados.' });
  })
);

router.get(
  '/verify-email',
  asyncHandler(async (req, res) => {
    const token = req.query.token;
    if (!token) throw badRequest('Token é obrigatório.');

    const [result] = await db.query(
      'UPDATE users SET email_verified = TRUE, email_verify_token = NULL WHERE email_verify_token = ? AND deleted_at IS NULL',
      [token]
    );
    if (result.affectedRows === 0) throw badRequest('Token inválido ou já utilizado.', 400);

    res.json({ message: 'E-mail confirmado com sucesso.' });
  })
);

router.post(
  '/resend-verification',
  authenticate,
  asyncHandler(async (req, res) => {
    const user = await findUserById(req.userId);
    if (user.email_verified) throw badRequest('E-mail já confirmado.');

    const token = crypto.randomBytes(24).toString('hex');
    await db.query('UPDATE users SET email_verify_token = ? WHERE id = ?', [token, user.id]);
    await sendVerificationEmail(user, token);

    res.json({ message: 'E-mail de confirmação reenviado.' });
  })
);

router.get(
  '/sessions',
  authenticate,
  asyncHandler(async (req, res) => {
    const [rows] = await db.query(
      `SELECT id, device_name, platform, ip_address, created_at, last_seen_at, revoked_at
       FROM user_sessions WHERE user_id = ? ORDER BY last_seen_at DESC, created_at DESC`,
      [req.userId]
    );
    res.json(rows.map((row) => ({ ...row, current: row.id === req.sessionId })));
  })
);

router.delete(
  '/sessions/:id',
  authenticate,
  asyncHandler(async (req, res) => {
    const [result] = await db.query(
      'UPDATE user_sessions SET revoked_at = NOW() WHERE id = ? AND user_id = ? AND revoked_at IS NULL',
      [req.params.id, req.userId]
    );
    if (result.affectedRows === 0) throw badRequest('Sessão não encontrada.', 404);

    await logAccess({ userId: req.userId, email: req.user.email, action: 'session_revoked', req, success: true });
    res.json({ message: 'Sessão revogada.' });
  })
);

router.delete(
  '/sessions',
  authenticate,
  asyncHandler(async (req, res) => {
    await revokeOtherSessions(req.userId, req.sessionId || null);
    await logAccess({ userId: req.userId, email: req.user.email, action: 'session_revoked', req, success: true });
    res.json({ message: 'Os outros dispositivos foram desconectados.' });
  })
);

router.post(
  '/2fa/setup',
  authenticate,
  asyncHandler(async (req, res) => {
    const secret = generateTotpSecret();
    await db.query('UPDATE users SET two_factor_secret = ? WHERE id = ?', [secret, req.userId]);

    const otpauthUrl = totpUri(req.user.email, secret);
    res.json({ secret, otpauth_url: otpauthUrl, qr_code_data_url: await qrcode.toDataURL(otpauthUrl) });
  })
);

router.post(
  '/2fa/enable',
  authenticate,
  asyncHandler(async (req, res) => {
    const { code } = req.body;
    if (!code) throw badRequest('Código é obrigatório.');

    const user = await findUserById(req.userId);
    if (!user.two_factor_secret) throw badRequest('Gere o segredo em /auth/2fa/setup antes de ativar.');
    if (!(await checkTotp(code, user.two_factor_secret))) throw badRequest('Código inválido.');

    await db.query('UPDATE users SET two_factor_enabled = TRUE WHERE id = ?', [req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', { two_factor_enabled: true });

    res.json({ message: 'Verificação em duas etapas ativada.' });
  })
);

router.post(
  '/2fa/disable',
  authenticate,
  asyncHandler(async (req, res) => {
    const { password } = req.body;
    if (!password) throw badRequest('Senha é obrigatória.');

    const user = await findUserById(req.userId);
    if (!(await bcrypt.compare(String(password), user.password_hash || ''))) throw badRequest('Senha incorreta.', 401);

    await db.query('UPDATE users SET two_factor_enabled = FALSE, two_factor_secret = NULL WHERE id = ?', [req.userId]);
    await audit(req.userId, 'user', req.userId, 'update', { two_factor_enabled: false });

    res.json({ message: 'Verificação em duas etapas desativada.' });
  })
);

/**
 * Exclusão de conta em modo lógico: preservamos os registros históricos e apenas
 * marcamos deleted_at, liberando o e-mail para novo cadastro. As tabelas filhas
 * têm ON DELETE CASCADE, que só dispararia numa exclusão física (DELETE), feita
 * por rotina administrativa de expurgo.
 */
router.delete(
  '/account',
  authenticate,
  asyncHandler(async (req, res) => {
    const { password } = req.body;
    if (!password) throw badRequest('Senha é obrigatória para excluir a conta.');

    const user = await findUserById(req.userId);
    if (!(await bcrypt.compare(String(password), user.password_hash || ''))) throw badRequest('Senha incorreta.', 401);

    await db.query(
      `UPDATE users SET deleted_at = NOW(), email = ?, reset_token = NULL, email_verify_token = NULL,
              two_factor_enabled = FALSE, two_factor_secret = NULL, pin_hash = NULL
       WHERE id = ?`,
      [`deleted_${user.id}@removed.local`, user.id]
    );
    await db.query('UPDATE user_sessions SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL', [user.id]);
    await audit(user.id, 'user', user.id, 'delete', { email: user.email });

    res.json({ message: 'Conta excluída.' });
  })
);

// Portabilidade de dados: um JSON com tudo que pertence ao usuário (spec §1).
const EXPORT_QUERIES = {
  accounts: 'SELECT * FROM accounts WHERE user_id = ?',
  categories: 'SELECT * FROM categories WHERE user_id = ?',
  transactions: 'SELECT * FROM transactions WHERE user_id = ?',
  credit_cards: 'SELECT * FROM credit_cards WHERE user_id = ?',
  card_invoices: 'SELECT * FROM card_invoices WHERE user_id = ?',
  budgets: 'SELECT * FROM budgets WHERE user_id = ?',
  goals: 'SELECT * FROM goals WHERE user_id = ?',
  goal_contributions: 'SELECT * FROM goal_contributions WHERE goal_id IN (SELECT id FROM goals WHERE user_id = ?)',
  investments: 'SELECT * FROM investments WHERE user_id = ?',
  investment_movements:
    'SELECT * FROM investment_movements WHERE investment_id IN (SELECT id FROM investments WHERE user_id = ?)',
  debts: 'SELECT * FROM debts WHERE user_id = ?',
  debt_payments: 'SELECT * FROM debt_payments WHERE debt_id IN (SELECT id FROM debts WHERE user_id = ?)',
  assets: 'SELECT * FROM assets WHERE user_id = ?',
  tags: 'SELECT * FROM tags WHERE user_id = ?',
  installments: 'SELECT * FROM installments WHERE user_id = ?',
  installment_items:
    'SELECT * FROM installment_items WHERE installment_id IN (SELECT id FROM installments WHERE user_id = ?)',
  recurring_transactions: 'SELECT * FROM recurring_transactions WHERE user_id = ?',
  financial_events: 'SELECT * FROM financial_events WHERE user_id = ?',
  notifications: 'SELECT * FROM notifications WHERE user_id = ?',
};

router.get(
  '/export',
  authenticate,
  asyncHandler(async (req, res) => {
    const data = { generated_at: new Date().toISOString(), user: sanitizeUser(await findUserById(req.userId)) };

    for (const [key, sql] of Object.entries(EXPORT_QUERIES)) {
      try {
        const [rows] = await db.query(sql, [req.userId]);
        data[key] = rows;
      } catch (err) {
        // Uma tabela ainda não criada não deve impedir a exportação do resto.
        console.error(`export ${key}:`, err.message);
        data[key] = [];
      }
    }

    res.setHeader('Content-Disposition', `attachment; filename="finance-control-${req.userId}.json"`);
    res.json(data);
  })
);

module.exports = router;
