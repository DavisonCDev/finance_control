// Auditoria, logs de acesso e feed de atividade familiar (spec §15, §38, §46).
const db = require('../db');

// Telemetria e nao-critica: roda em background sem segurar a resposta
// da requisicao (cada round-trip ao banco remoto custa latencia real).
// Os callers podem continuar usando `await` — resolve imediatamente.
function audit(userId, entity, entityId, action, changes = null) {
  db.query(
    'INSERT INTO audit_logs (user_id, entity, entity_id, action, changes) VALUES (?, ?, ?, ?, ?)',
    [userId, entity, entityId, action, changes ? JSON.stringify(changes) : null]
  ).catch(err => console.error('audit:', err.message));
}

function logAccess({ userId = null, email = null, action, req = null, success = true }) {
  db.query(
    'INSERT INTO access_logs (user_id, email, action, ip_address, user_agent, success) VALUES (?, ?, ?, ?, ?, ?)',
    [userId, email, action, req ? clientIp(req) : null, req ? String(req.headers['user-agent'] || '').slice(0, 255) : null, success]
  ).catch(err => console.error('logAccess:', err.message));
}

function familyActivity({ familyId, userId, action, entity = null, entityId = null, description = null, amount = null }) {
  if (!familyId) return;
  db.query(
    `INSERT INTO family_activity (family_id, user_id, action, entity, entity_id, description, amount)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [familyId, userId, action, entity, entityId, description, amount]
  ).catch(err => console.error('familyActivity:', err.message));
}

function clientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) return String(forwarded).split(',')[0].trim().slice(0, 45);
  return (req.ip || req.socket?.remoteAddress || '').replace('::ffff:', '').slice(0, 45);
}

module.exports = { audit, logAccess, familyActivity, clientIp };
