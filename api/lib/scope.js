// Escopo de visibilidade: separa finanças pessoais das compartilhadas (spec §2).
//
// Regras:
// - O usuário sempre vê os próprios registros.
// - Registros marcados com family_id são visíveis aos membros daquela família,
//   respeitando o papel: admin e membros com can_view_all veem tudo; membros comuns
//   veem os recursos compartilhados; dependentes veem apenas o que é seu.
const db = require('../db');

async function membershipsOf(userId) {
  const [rows] = await db.query(
    `SELECT fm.family_id, fm.role, fm.can_view_all, fm.can_manage_budget, f.name AS family_name, f.owner_id
     FROM family_members fm
     JOIN families f ON f.id = fm.family_id
     WHERE fm.user_id = ?`,
    [userId]
  );
  return rows;
}

async function familyIdsVisibleTo(userId) {
  const memberships = await membershipsOf(userId);
  return memberships
    .filter(m => m.role === 'admin' || m.can_view_all || m.role === 'member' || m.role === 'viewer')
    .map(m => m.family_id);
}

// Cláusula SQL reutilizável: registros próprios OU da família visível.
// `alias` é o prefixo da tabela (ex.: 't' para transactions).
async function visibilityClause(userId, alias = 't') {
  const familyIds = await familyIdsVisibleTo(userId);
  if (familyIds.length === 0) {
    return { sql: `${alias}.user_id = ?`, params: [userId] };
  }
  const placeholders = familyIds.map(() => '?').join(', ');
  return {
    sql: `(${alias}.user_id = ? OR ${alias}.family_id IN (${placeholders}))`,
    params: [userId, ...familyIds],
  };
}

async function roleInFamily(userId, familyId) {
  const [rows] = await db.query(
    'SELECT role, can_view_all, can_manage_budget FROM family_members WHERE user_id = ? AND family_id = ?',
    [userId, familyId]
  );
  return rows[0] || null;
}

async function requireFamilyRole(userId, familyId, roles) {
  const membership = await roleInFamily(userId, familyId);
  if (!membership) {
    const error = new Error('Você não pertence a esta família.');
    error.status = 403;
    throw error;
  }
  if (roles && !roles.includes(membership.role)) {
    const error = new Error('Permissão insuficiente para esta ação.');
    error.status = 403;
    throw error;
  }
  return membership;
}

// Confere se o usuário pode usar um family_id ao criar/editar um recurso.
async function assertCanUseFamily(userId, familyId) {
  if (!familyId) return null;
  const membership = await roleInFamily(userId, familyId);
  if (!membership || membership.role === 'dependent') {
    const error = new Error('Sem permissão para vincular este recurso à família.');
    error.status = 403;
    throw error;
  }
  return membership;
}

// Ids dos usuários que compõem a visão consolidada da família (spec §36).
async function familyMemberIds(familyId) {
  const [rows] = await db.query('SELECT user_id FROM family_members WHERE family_id = ?', [familyId]);
  return rows.map(r => r.user_id);
}

module.exports = {
  membershipsOf,
  familyIdsVisibleTo,
  visibilityClause,
  roleInFamily,
  requireFamilyRole,
  assertCanUseFamily,
  familyMemberIds,
};
