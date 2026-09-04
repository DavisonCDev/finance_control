// Lançamentos: receitas, despesas, transferências e ajustes (spec §5, §12, §23, §25).
//
// Todo efeito colateral (saldo de conta, fatura de cartão, transferência) é
// delegado ao motor contábil em lib/ledger.
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit, familyActivity } = require('../lib/audit');
const scope = require('../lib/scope');
const ledger = require('../lib/ledger');
const { applyRules } = require('../lib/rules');
const gamification = require('../lib/gamification');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

const TYPES = ['income', 'expense', 'transfer', 'adjustment'];
const STATUSES = ['pending', 'cleared', 'scheduled', 'cancelled'];

function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 });
}

function notFound(message) {
  return Object.assign(new Error(message), { status: 404 });
}

function parseBool(value, fallback = undefined) {
  if (value === undefined || value === null || value === '') return fallback;
  return value === true || value === 'true' || value === 1 || value === '1';
}

function splitTags(value) {
  return value ? String(value).split(',') : [];
}

function serialize(row) {
  return { ...row, tag_names: splitTags(row.tag_names), attachment_count: Number(row.attachment_count || 0) };
}

// Janelas de tempo prontas usadas pelos atalhos da UI (spec §12).
function periodRange(period) {
  const today = dates.toIsoDate(new Date());
  if (period === 'today') return { from: today, to: today };
  if (period === 'week') {
    const d = dates.parseDate(today);
    const start = dates.addDays(today, -((d.getDay() + 6) % 7)); // semana começa na segunda
    return { from: dates.toIsoDate(start), to: dates.toIsoDate(dates.addDays(start, 6)) };
  }
  if (period === 'month') return dates.monthRange(today.slice(0, 7)) && {
    from: dates.monthRange(today.slice(0, 7)).start,
    to: dates.monthRange(today.slice(0, 7)).end,
  };
  if (period === 'year') return { from: `${today.slice(0, 4)}-01-01`, to: `${today.slice(0, 4)}-12-31` };
  throw badRequest("Período inválido. Use 'today', 'week', 'month' ou 'year'.");
}

/**
 * Monta a cláusula WHERE compartilhada por listagem, contagem e resumo.
 * Sempre respeita soft delete e o escopo de visibilidade familiar.
 */
async function buildFilters(req) {
  const q = req.query;
  const visibility = await scope.visibilityClause(req.userId, 't');
  const conditions = ['t.deleted_at IS NULL', visibility.sql];
  const params = [...visibility.params];

  let from = q.from || null;
  let to = q.to || null;

  if (q.period) {
    const range = periodRange(q.period);
    from = range.from;
    to = range.to;
  } else if (q.month) {
    if (!/^\d{4}-\d{2}$/.test(q.month)) throw badRequest('Use o formato YYYY-MM no parâmetro month.');
    const range = dates.monthRange(q.month);
    from = range.start;
    to = range.end;
  }

  if (from) {
    conditions.push('t.date >= ?');
    params.push(from);
  }
  if (to) {
    conditions.push('t.date <= ?');
    params.push(to);
  }

  if (q.type) {
    if (!TYPES.includes(q.type)) throw badRequest(`Tipo inválido. Use: ${TYPES.join(', ')}.`);
    conditions.push('t.type = ?');
    params.push(q.type);
  }
  if (q.types) {
    const list = String(q.types).split(',').map(s => s.trim()).filter(Boolean);
    const invalid = list.filter(t => !TYPES.includes(t));
    if (invalid.length > 0) throw badRequest(`Tipo inválido: ${invalid.join(', ')}.`);
    if (list.length > 0) {
      conditions.push(`t.type IN (${list.map(() => '?').join(', ')})`);
      params.push(...list);
    }
  }

  // Filtrar por categoria inclui as subcategorias dela.
  if (q.category_id) {
    conditions.push('(c.id = ? OR c.parent_id = ?)');
    params.push(q.category_id, q.category_id);
  }
  if (q.account_id) {
    conditions.push('(t.account_id = ? OR t.transfer_account_id = ?)');
    params.push(q.account_id, q.account_id);
  }
  if (q.card_id) {
    conditions.push('t.card_id = ?');
    params.push(q.card_id);
  }
  if (q.person_id) {
    conditions.push('t.person_id = ?');
    params.push(q.person_id);
  }
  if (q.family_id) {
    conditions.push('t.family_id = ?');
    params.push(q.family_id);
  }
  if (q.status) {
    if (!STATUSES.includes(q.status)) throw badRequest(`Situação inválida. Use: ${STATUSES.join(', ')}.`);
    conditions.push('t.status = ?');
    params.push(q.status);
  }
  if (q.min_amount !== undefined && q.min_amount !== '') {
    conditions.push('t.amount >= ?');
    params.push(Number(q.min_amount));
  }
  if (q.max_amount !== undefined && q.max_amount !== '') {
    conditions.push('t.amount <= ?');
    params.push(Number(q.max_amount));
  }
  if (q.tag_id) {
    conditions.push('EXISTS (SELECT 1 FROM transaction_tags tt WHERE tt.transaction_id = t.id AND tt.tag_id = ?)');
    params.push(q.tag_id);
  }
  if (q.tag) {
    conditions.push(`EXISTS (SELECT 1 FROM transaction_tags tt JOIN tags tg2 ON tg2.id = tt.tag_id
                             WHERE tt.transaction_id = t.id AND tg2.name = ?)`);
    params.push(q.tag);
  }
  if (q.q) {
    conditions.push('(t.description LIKE ? OR t.notes LIKE ? OR t.location LIKE ?)');
    const like = `%${q.q}%`;
    params.push(like, like, like);
  }

  // Transferências entram por padrão, mas relatórios costumam querer escondê-las.
  if (parseBool(q.include_transfers, true) === false) {
    conditions.push("t.type <> 'transfer'");
  }

  return { where: conditions.join(' AND '), params };
}

const ORDERS = {
  date_desc: 't.date DESC, t.id DESC',
  date_asc: 't.date ASC, t.id ASC',
  amount_desc: 't.amount DESC, t.id DESC',
  amount_asc: 't.amount ASC, t.id ASC',
};

// FROM mínimo (com categorias) usado por contagem e resumo.
const COUNT_FROM = `
  FROM transactions t
  LEFT JOIN categories c ON t.category_id = c.id
`;

// GET / — listagem filtrada com total e resumo.
router.get('/', asyncHandler(async (req, res) => {
  const { where, params } = await buildFilters(req);
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 1000);
  const offset = Math.max(Number(req.query.offset) || 0, 0);
  const order = ORDERS[req.query.order || 'date_desc'];
  if (!order) throw badRequest("Ordenação inválida. Use 'date_desc', 'date_asc', 'amount_desc' ou 'amount_asc'.");

  const [rows] = await db.query(
    `${ledger.TRANSACTION_SELECT} WHERE ${where} ORDER BY ${order} LIMIT ? OFFSET ?`,
    [...params, limit, offset]
  );

  const [totals] = await db.query(`SELECT COUNT(*) AS total ${COUNT_FROM} WHERE ${where}`, params);

  // Resumo ignora transferências: mover dinheiro entre contas não é receita nem despesa.
  const [summary] = await db.query(
    `SELECT
       COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS income,
       COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS expense,
       COUNT(*) AS count
     ${COUNT_FROM}
     WHERE ${where} AND t.type <> 'transfer'`,
    params
  );

  const income = Number(summary[0]?.income || 0);
  const expense = Number(summary[0]?.expense || 0);

  res.json({
    transactions: rows.map(serialize),
    total: Number(totals[0]?.total || 0),
    summary: {
      income,
      expense,
      balance: Number((income - expense).toFixed(2)),
      count: Number(summary[0]?.count || 0),
    },
  });
}));

// POST /transfer — transferência entre contas do próprio usuário.
router.post('/transfer', asyncHandler(async (req, res) => {
  const { account_id, transfer_account_id, amount, date, description, notes } = req.body;
  if (!account_id || !transfer_account_id) throw badRequest('Informe a conta de origem e a conta de destino.');
  if (Number(account_id) === Number(transfer_account_id)) throw badRequest('Conta de origem e destino devem ser diferentes.');
  const value = Number(amount);
  if (!value || Number.isNaN(value) || value <= 0) throw badRequest('Informe um valor maior que zero.');

  const origin = await assertOwnAccount(req.userId, account_id);
  await assertOwnAccount(req.userId, transfer_account_id);

  // Transferência é UM registro (origem + destino) e nunca conta como despesa
  // nem receita nos relatórios (spec §25).
  const transaction = await withTransaction(conn => ledger.createTransaction(conn, req.userId, {
    account_id,
    transfer_account_id,
    type: 'transfer',
    amount: value,
    date: date || dates.toIsoDate(new Date()),
    description: description || 'Transferência entre contas',
    notes: notes || null,
    currency: origin.currency,
    source: 'manual',
  }));

  await gamification.registerActivity(req.userId, transaction.date);
  await audit(req.userId, 'transaction', transaction.id, 'create', { kind: 'transfer' });
  res.status(201).json(serialize(transaction));
}));

// POST /transfer/member — transferência entre membros da família (spec §25).
router.post('/transfer/member', asyncHandler(async (req, res) => {
  const { transfer_to_user_id, family_id, account_id, amount, date, description } = req.body;
  if (!transfer_to_user_id || !family_id || !account_id) {
    throw badRequest('Informe family_id, account_id e transfer_to_user_id.');
  }
  const value = Number(amount);
  if (!value || Number.isNaN(value) || value <= 0) throw badRequest('Informe um valor maior que zero.');
  if (Number(transfer_to_user_id) === Number(req.userId)) throw badRequest('Escolha outro membro da família como destino.');

  await scope.assertCanUseFamily(req.userId, family_id);
  const memberIds = (await scope.familyMemberIds(family_id)).map(Number);
  if (!memberIds.includes(Number(req.userId)) || !memberIds.includes(Number(transfer_to_user_id))) {
    throw Object.assign(new Error('Remetente e destinatário precisam ser membros desta família.'), { status: 403 });
  }

  const origin = await assertOwnAccount(req.userId, account_id);

  // O motor contábil exige uma conta de destino para type='transfer'; usamos a
  // conta informada ou a primeira conta ativa do membro que recebe.
  let destinationId = req.body.transfer_account_id || null;
  if (destinationId) {
    const [rows] = await db.query(
      'SELECT id FROM accounts WHERE id = ? AND user_id = ?',
      [destinationId, transfer_to_user_id]
    );
    if (rows.length === 0) throw notFound('Conta de destino não pertence ao membro informado.');
  } else {
    const [rows] = await db.query(
      'SELECT id FROM accounts WHERE user_id = ? AND active = TRUE ORDER BY id LIMIT 1',
      [transfer_to_user_id]
    );
    if (rows.length === 0) {
      throw badRequest('O membro de destino não possui conta ativa para receber a transferência. Informe transfer_account_id.');
    }
    destinationId = rows[0].id;
  }
  if (Number(destinationId) === Number(account_id)) throw badRequest('Conta de origem e destino devem ser diferentes.');

  const transaction = await withTransaction(conn => ledger.createTransaction(conn, req.userId, {
    account_id,
    transfer_account_id: destinationId,
    transfer_to_user_id,
    family_id,
    type: 'transfer',
    amount: value,
    date: date || dates.toIsoDate(new Date()),
    description: description || 'Transferência para membro da família',
    currency: origin.currency,
    source: 'manual',
  }));

  await gamification.registerActivity(req.userId, transaction.date);
  await audit(req.userId, 'transaction', transaction.id, 'create', { kind: 'member_transfer', to: transfer_to_user_id });
  await familyActivity({
    familyId: family_id,
    userId: req.userId,
    action: 'transaction_created',
    entity: 'transaction',
    entityId: transaction.id,
    description: transaction.description,
    amount: value,
  });

  res.status(201).json(serialize(transaction));
}));

// POST /bulk — criação em lote numa única transação de banco.
router.post('/bulk', asyncHandler(async (req, res) => {
  const items = Array.isArray(req.body?.transactions) ? req.body.transactions : null;
  if (!items || items.length === 0) throw badRequest('Envie a lista de lançamentos em transactions.');
  if (items.length > 500) throw badRequest('Envie no máximo 500 lançamentos por vez.');

  const errors = [];
  const prepared = [];

  for (let index = 0; index < items.length; index += 1) {
    try {
      const base = buildPayload(items[index], req);
      const ruled = await applyRules(req.userId, base);
      const payload = {
        ...ruled.transaction,
        tagIds: [...new Set([...(base.tagIds || []), ...ruled.tagIds])],
      };
      await validateReferences(req.userId, payload);
      prepared.push({ index, payload });
    } catch (err) {
      errors.push({ index, error: err.message });
    }
  }

  const ids = await withTransaction(async conn => {
    const created = [];
    for (const item of prepared) {
      const row = await ledger.createTransaction(conn, req.userId, item.payload);
      created.push(row.id);
    }
    return created;
  });

  if (ids.length > 0) {
    await gamification.registerActivity(req.userId, null);
    await gamification.checkTransactionAchievements(req.userId);
    await audit(req.userId, 'transaction', null, 'create', { bulk: ids });
  }

  res.status(errors.length > 0 && ids.length === 0 ? 400 : 201).json({ created: ids.length, ids, errors });
}));

// POST /bulk/categorize — recategoriza vários lançamentos de uma vez.
router.post('/bulk/categorize', asyncHandler(async (req, res) => {
  const ids = normalizeIds(req.body?.ids);
  const { category_id } = req.body;
  if (!category_id) throw badRequest('Informe a category_id de destino.');

  const [categories] = await db.query(
    'SELECT id FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL)',
    [category_id, req.userId]
  );
  if (categories.length === 0) throw notFound('Categoria não encontrada.');

  const placeholders = ids.map(() => '?').join(', ');
  const [result] = await db.query(
    `UPDATE transactions SET category_id = ?
     WHERE id IN (${placeholders}) AND user_id = ? AND deleted_at IS NULL`,
    [category_id, ...ids, req.userId]
  );

  await audit(req.userId, 'transaction', null, 'update', { bulk_categorize: ids, category_id });
  res.json({ updated: result.affectedRows, category_id });
}));

// DELETE /bulk — exclui em lote revertendo os efeitos de cada lançamento.
router.delete('/bulk', asyncHandler(async (req, res) => {
  const ids = normalizeIds(req.body?.ids);

  const outcome = await withTransaction(async conn => {
    const deleted = [];
    const errors = [];
    for (const id of ids) {
      try {
        await ledger.deleteTransaction(conn, req.userId, id);
        deleted.push(id);
      } catch (err) {
        errors.push({ id, error: err.message });
      }
    }
    return { deleted, errors };
  });

  await audit(req.userId, 'transaction', null, 'delete', { bulk: outcome.deleted });
  res.json({ deleted: outcome.deleted.length, ids: outcome.deleted, errors: outcome.errors });
}));

// GET /:id — detalhe com tags e anexos.
router.get('/:id', asyncHandler(async (req, res) => {
  const visibility = await scope.visibilityClause(req.userId, 't');
  const [rows] = await db.query(
    `${ledger.TRANSACTION_SELECT} WHERE t.id = ? AND t.deleted_at IS NULL AND ${visibility.sql}`,
    [req.params.id, ...visibility.params]
  );
  if (rows.length === 0) throw notFound('Transação não encontrada.');

  const [tags] = await db.query(
    `SELECT tg.id, tg.name, tg.color FROM transaction_tags tt
     JOIN tags tg ON tg.id = tt.tag_id
     WHERE tt.transaction_id = ? ORDER BY tg.name`,
    [rows[0].id]
  );
  const [attachments] = await db.query(
    'SELECT id, file_name, kind, mime_type FROM attachments WHERE transaction_id = ? ORDER BY id',
    [rows[0].id]
  );

  res.json({ ...serialize(rows[0]), tags, attachments });
}));

// POST / — criação manual, com regras automáticas aplicadas antes de gravar.
router.post('/', asyncHandler(async (req, res) => {
  const base = buildPayload(req.body, req);
  const ruled = await applyRules(req.userId, base);
  const payload = {
    ...ruled.transaction,
    tagIds: [...new Set([...(base.tagIds || []), ...ruled.tagIds])],
  };

  // Regra com require_confirmation: devolve a sugestão sem gravar nada.
  if (ruled.requiresConfirmation && req.body?.confirmed !== true) {
    return res.status(409).json({
      requires_confirmation: true,
      rule_message: 'Este lançamento exige confirmação por uma regra automática.',
      suggested: payload,
    });
  }

  if (payload.family_id) await scope.assertCanUseFamily(req.userId, payload.family_id);
  await validateReferences(req.userId, payload);

  const transaction = await withTransaction(conn => ledger.createTransaction(conn, req.userId, payload));

  await gamification.registerActivity(req.userId, transaction.date);
  await gamification.checkTransactionAchievements(req.userId);
  await audit(req.userId, 'transaction', transaction.id, 'create', { applied_rules: ruled.appliedRuleIds });

  if (transaction.family_id) {
    await familyActivity({
      familyId: transaction.family_id,
      userId: req.userId,
      action: 'transaction_created',
      entity: 'transaction',
      entityId: transaction.id,
      description: transaction.description,
      amount: transaction.amount,
    });
  }

  res.status(201).json(serialize(transaction));
}));

// PUT /:id — atualiza revertendo o efeito antigo e aplicando o novo.
router.put('/:id', asyncHandler(async (req, res) => {
  const [existing] = await db.query(
    'SELECT * FROM transactions WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
    [req.params.id, req.userId]
  );
  if (existing.length === 0) throw notFound('Transação não encontrada.');

  const body = req.body || {};
  if (body.type && !TYPES.includes(body.type)) throw badRequest(`Tipo inválido. Use: ${TYPES.join(', ')}.`);
  if (body.status && !STATUSES.includes(body.status)) throw badRequest(`Situação inválida. Use: ${STATUSES.join(', ')}.`);
  if (body.family_id) await scope.assertCanUseFamily(req.userId, body.family_id);

  const payload = {};
  for (const field of [
    'account_id', 'category_id', 'card_id', 'type', 'amount', 'date', 'time', 'description',
    'notes', 'family_id', 'person_id', 'location', 'currency', 'status', 'transfer_account_id',
    'goal_id', 'is_refund',
  ]) {
    if (body[field] !== undefined) payload[field] = body[field];
  }
  const tagIds = body.tagIds || body.tag_ids;
  if (Array.isArray(tagIds)) payload.tagIds = tagIds.map(Number).filter(Boolean);

  await validateReferences(req.userId, { ...existing[0], ...payload });

  const transaction = await withTransaction(conn => ledger.updateTransaction(conn, req.userId, req.params.id, payload));

  await audit(req.userId, 'transaction', transaction.id, 'update', { before: existing[0], changes: payload });
  res.json(serialize(transaction));
}));

// DELETE /:id — remove e reverte os efeitos.
router.delete('/:id', asyncHandler(async (req, res) => {
  const removed = await withTransaction(conn => ledger.deleteTransaction(conn, req.userId, req.params.id));
  await audit(req.userId, 'transaction', removed.id, 'delete', removed);
  res.json({ message: 'Lançamento excluído.', id: removed.id });
}));

// --- Helpers -----------------------------------------------------------------

function normalizeIds(value) {
  const ids = Array.isArray(value) ? value.map(Number).filter(Boolean) : [];
  if (ids.length === 0) throw badRequest('Envie a lista de ids.');
  if (ids.length > 500) throw badRequest('Envie no máximo 500 ids por vez.');
  return ids;
}

// Normaliza o corpo da requisição no formato aceito por lib/ledger.
function buildPayload(body = {}, req) {
  const type = body.type;
  if (!type || !TYPES.includes(type)) throw badRequest(`Tipo é obrigatório. Use: ${TYPES.join(', ')}.`);
  if (body.status && !STATUSES.includes(body.status)) throw badRequest(`Situação inválida. Use: ${STATUSES.join(', ')}.`);

  const amount = Number(body.amount);
  if (Number.isNaN(amount) || (type !== 'adjustment' && amount <= 0)) {
    throw badRequest('Informe um valor válido maior que zero.');
  }
  if (!body.date) throw badRequest('A data é obrigatória.');

  const tagIds = body.tagIds || body.tag_ids;

  return {
    account_id: body.account_id || null,
    category_id: body.category_id || null,
    card_id: body.card_id || null,
    type,
    amount,
    date: String(body.date).slice(0, 10),
    time: body.time || null,
    description: body.description || null,
    notes: body.notes || null,
    family_id: body.family_id || null,
    person_id: body.person_id || null,
    location: body.location || null,
    latitude: body.latitude ?? null,
    longitude: body.longitude ?? null,
    currency: body.currency || req.user.currency || 'BRL',
    original_amount: body.original_amount ?? null,
    exchange_rate: body.exchange_rate ?? null,
    status: body.status || 'cleared',
    transfer_account_id: body.transfer_account_id || null,
    transfer_to_user_id: body.transfer_to_user_id || null,
    installment_id: body.installment_id || null,
    installment_number: body.installment_number || null,
    recurring_id: body.recurring_id || null,
    goal_id: body.goal_id || null,
    investment_id: body.investment_id || null,
    debt_id: body.debt_id || null,
    import_hash: body.import_hash || null,
    client_uuid: body.client_uuid || null,
    source: body.source || 'manual',
    is_refund: parseBool(body.is_refund, false),
    tagIds: Array.isArray(tagIds) ? tagIds.map(Number).filter(Boolean) : [],
  };
}

async function assertOwnAccount(userId, accountId) {
  const [rows] = await db.query('SELECT * FROM accounts WHERE id = ? AND user_id = ?', [accountId, userId]);
  if (rows.length === 0) throw notFound('Conta não encontrada.');
  return rows[0];
}

/**
 * Garante que conta, cartão e categoria informados pertencem ao usuário
 * (ou a uma família visível, no caso de recursos compartilhados).
 */
async function validateReferences(userId, payload) {
  if (payload.account_id) {
    const visibility = await scope.visibilityClause(userId, 'a');
    const [rows] = await db.query(
      `SELECT a.id FROM accounts a WHERE a.id = ? AND ${visibility.sql}`,
      [payload.account_id, ...visibility.params]
    );
    if (rows.length === 0) throw notFound('Conta não encontrada.');
  }
  if (payload.transfer_account_id) {
    const visibility = await scope.visibilityClause(userId, 'a');
    const [rows] = await db.query(
      `SELECT a.id FROM accounts a WHERE a.id = ? AND ${visibility.sql}`,
      [payload.transfer_account_id, ...visibility.params]
    );
    if (rows.length === 0) throw notFound('Conta de destino não encontrada.');
  }
  if (payload.card_id) {
    const visibility = await scope.visibilityClause(userId, 'cc');
    const [rows] = await db.query(
      `SELECT cc.id FROM credit_cards cc WHERE cc.id = ? AND ${visibility.sql}`,
      [payload.card_id, ...visibility.params]
    );
    if (rows.length === 0) throw notFound('Cartão não encontrado.');
  }
  if (payload.category_id) {
    const [rows] = await db.query(
      'SELECT id FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL)',
      [payload.category_id, userId]
    );
    if (rows.length === 0) throw notFound('Categoria não encontrada.');
  }
  if (Array.isArray(payload.tagIds) && payload.tagIds.length > 0) {
    const placeholders = payload.tagIds.map(() => '?').join(', ');
    const [rows] = await db.query(
      `SELECT id FROM tags WHERE id IN (${placeholders}) AND user_id = ?`,
      [...payload.tagIds, userId]
    );
    if (rows.length !== payload.tagIds.length) throw notFound('Uma ou mais tags não foram encontradas.');
  }
}

module.exports = router;
