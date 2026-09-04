// Criação de notificações respeitando preferências, horários silenciosos e dedupe (spec §14).
const db = require('../db');

async function preferenceFor(userId, type) {
  const [rows] = await db.query(
    'SELECT * FROM notification_preferences WHERE user_id = ? AND type = ?',
    [userId, type]
  );
  return rows[0] || null;
}

function insideQuietHours(pref, now = new Date()) {
  if (!pref?.quiet_hours_start || !pref?.quiet_hours_end) return false;
  const minutes = now.getHours() * 60 + now.getMinutes();
  const [sh, sm] = String(pref.quiet_hours_start).split(':').map(Number);
  const [eh, em] = String(pref.quiet_hours_end).split(':').map(Number);
  const start = sh * 60 + sm;
  const end = eh * 60 + em;
  return start <= end ? minutes >= start && minutes < end : minutes >= start || minutes < end;
}

/**
 * Cria uma notificação. Retorna o id criado ou null quando suprimida
 * (preferência desativada) ou duplicada (mesma dedupe_key).
 */
async function notify({
  userId,
  type,
  title,
  message,
  severity = 'info',
  entity = null,
  entityId = null,
  dedupeKey = null,
  scheduledAt = null,
}) {
  const pref = await preferenceFor(userId, type);
  if (pref && !pref.enabled) return null;

  const quiet = insideQuietHours(pref);
  const scheduled = scheduledAt || (quiet ? nextMorning(pref) : null);

  try {
    const [result] = await db.query(
      `INSERT INTO notifications
         (user_id, title, message, type, severity, entity, entity_id, dedupe_key, scheduled_at, sent_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [userId, title, message, type, severity, entity, entityId, dedupeKey, scheduled, scheduled ? null : new Date()]
    );
    return result.insertId;
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') return null; // já notificado
    throw err;
  }
}

function nextMorning(pref) {
  const [eh, em] = String(pref.quiet_hours_end || '08:00').split(':').map(Number);
  const date = new Date();
  date.setSeconds(0, 0);
  if (date.getHours() * 60 + date.getMinutes() >= eh * 60 + em) date.setDate(date.getDate() + 1);
  date.setHours(eh, em);
  return date;
}

async function ensureDefaultPreferences(userId) {
  const types = [
    'bill_due', 'card_due', 'invoice_closed', 'budget_near', 'budget_over', 'low_balance',
    'installment_due', 'income_missing', 'family_expense', 'family_budget', 'family_event',
    'goal', 'insight', 'system',
  ];
  for (const type of types) {
    await db.query('INSERT IGNORE INTO notification_preferences (user_id, type) VALUES (?, ?)', [userId, type]);
  }
}

module.exports = { notify, ensureDefaultPreferences, preferenceFor, insideQuietHours };
