// Contas: carteiras, bancos, dinheiro físico, investimentos e contas conjuntas (spec §3).
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const scope = require('../lib/scope');
const ledger = require('../lib/ledger');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

const ACCOUNT_TYPES = [
  'checking', 'savings', 'digital', 'cash', 'investment',
  'salary', 'joint', 'international', 'other',
];

// Efeito de cada lançamento sobre o saldo desta conta. Espelha lib/ledger:
// transferência move valor entre contas, compra no cartão não toca no saldo.
const BALANCE_EFFECT = `
  CASE
    WHEN t.status IN ('cancelled', 'scheduled') THEN 0
    WHEN t.type = 'transfer' AND t.account_id = %ACC% THEN -t.amount
    WHEN t.type = 'transfer' AND t.transfer_account_id = %ACC% THEN t.amount
    WHEN t.card_id IS NOT NULL THEN 0
    WHEN t.account_id <> %ACC% THEN 0
    WHEN t.type IN ('income', 'adjustment') THEN t.amount
    WHEN t.type = 'expense' THEN -t.amount
    ELSE 0
  END`;

function effectFor(accountRef) {
  return BALANCE_EFFECT.replace(/%ACC%/g, accountRef);
}

function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 });
}

function parseBool(value) {
  if (value === undefined || value === null || value === '') return undefined;
  return value === true || value === 'true' || value === 1 || value === '1';
}

// Carrega a conta respeitando o escopo de visibilidade (própria ou da família).
async function loadVisibleAccount(userId, id) {
  const visibility = await scope.visibilityClause(userId, 'a');
  const [rows] = await db.query(
    `SELECT a.*, f.name AS family_name, (a.user_id = ?) AS is_own
     FROM accounts a
     LEFT JOIN families f ON f.id = a.family_id
     WHERE a.id = ? AND ${visibility.sql}`,
    [userId, id, ...visibility.params]
  );
  if (rows.length === 0) throw Object.assign(new Error('Conta não encontrada.'), { status: 404 });
  return rows[0];
}

async function loadOwnAccount(userId, id) {
  const [rows] = await db.query('SELECT * FROM accounts WHERE id = ? AND user_id = ?', [id, userId]);
  if (rows.length === 0) throw Object.assign(new Error('Conta não encontrada.'), { status: 404 });
  return rows[0];
}

// GET / — contas próprias + compartilhadas das famílias visíveis.
router.get('/', asyncHandler(async (req, res) => {
  const visibility = await scope.visibilityClause(req.userId, 'a');
  const params = [req.userId, ...visibility.params];
  let sql = `SELECT a.*, f.name AS family_name, (a.user_id = ?) AS is_own
             FROM accounts a
             LEFT JOIN families f ON f.id = a.family_id
             WHERE ${visibility.sql}`;

  // Conta de outro membro só aparece quando marcada como compartilhada.
  sql += ' AND (a.user_id = ? OR a.shared = TRUE)';
  params.push(req.userId);

  const active = parseBool(req.query.active);
  if (active !== undefined) {
    sql += ' AND a.active = ?';
    params.push(active ? 1 : 0);
  }
  if (req.query.type) {
    sql += ' AND a.type = ?';
    params.push(req.query.type);
  }

  sql += ' ORDER BY a.name';

  const [rows] = await db.query(sql, params);
  res.json(rows);
}));

// GET /:id — detalhe com conferência de saldo.
router.get('/:id', asyncHandler(async (req, res) => {
  const account = await loadVisibleAccount(req.userId, req.params.id);

  const [check] = await db.query(
    `SELECT COALESCE(SUM(${effectFor('?')}), 0) AS effects
     FROM transactions t
     WHERE t.deleted_at IS NULL AND (t.account_id = ? OR t.transfer_account_id = ?)`,
    [account.id, account.id, account.id, account.id, account.id]
  );

  const effects = Number(check[0]?.effects || 0);
  const expected = Number(account.initial_balance || 0) + effects;

  res.json({
    ...account,
    balance_check: {
      initial_balance: Number(account.initial_balance || 0),
      transactions_effect: effects,
      expected_balance: expected,
      current_balance: Number(account.current_balance || 0),
      difference: Number((Number(account.current_balance || 0) - expected).toFixed(2)),
    },
  });
}));

// GET /:id/statement — extrato com saldo corrente linha a linha.
router.get('/:id/statement', asyncHandler(async (req, res) => {
  const account = await loadVisibleAccount(req.userId, req.params.id);
  const from = req.query.from || null;
  const to = req.query.to || null;

  // Saldo inicial do extrato: tudo o que aconteceu antes do período.
  let opening = Number(account.initial_balance || 0);
  if (from) {
    const [before] = await db.query(
      `SELECT COALESCE(SUM(${effectFor('?')}), 0) AS effects
       FROM transactions t
       WHERE t.deleted_at IS NULL AND t.date < ?
         AND (t.account_id = ? OR t.transfer_account_id = ?)`,
      [account.id, account.id, account.id, from, account.id, account.id]
    );
    opening += Number(before[0]?.effects || 0);
  }

  const params = [account.id, account.id, account.id, account.id, account.id];
  let sql = `${ledger.TRANSACTION_SELECT.replace('SELECT t.*,', `SELECT t.*, (${effectFor('?')}) AS balance_effect,`)}
             WHERE t.deleted_at IS NULL AND (t.account_id = ? OR t.transfer_account_id = ?)`;
  if (from) {
    sql += ' AND t.date >= ?';
    params.push(from);
  }
  if (to) {
    sql += ' AND t.date <= ?';
    params.push(to);
  }
  sql += ' ORDER BY t.date ASC, t.id ASC';

  const [rows] = await db.query(sql, params);

  let running = opening;
  const entries = rows.map(row => {
    running += Number(row.balance_effect || 0);
    return {
      ...row,
      tag_names: row.tag_names ? row.tag_names.split(',') : [],
      balance_effect: Number(row.balance_effect || 0),
      running_balance: Number(running.toFixed(2)),
    };
  });

  res.json({
    account: { id: account.id, name: account.name, type: account.type, currency: account.currency },
    from,
    to,
    opening_balance: Number(opening.toFixed(2)),
    closing_balance: Number(running.toFixed(2)),
    count: entries.length,
    transactions: entries,
  });
}));

// POST / — cria conta.
router.post('/', asyncHandler(async (req, res) => {
  const { name, type, initial_balance, currency, family_id, shared, active } = req.body;
  if (!name || !String(name).trim()) throw badRequest('Nome da conta é obrigatório.');
  if (type && !ACCOUNT_TYPES.includes(type)) throw badRequest(`Tipo de conta inválido. Use: ${ACCOUNT_TYPES.join(', ')}.`);

  const initial = initial_balance === undefined || initial_balance === null ? 0 : Number(initial_balance);
  if (Number.isNaN(initial)) throw badRequest('Saldo inicial inválido.');

  if (family_id) await scope.assertCanUseFamily(req.userId, family_id);

  const [result] = await db.query(
    `INSERT INTO accounts (user_id, name, type, initial_balance, current_balance, active, family_id, shared, currency)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      req.userId, String(name).trim(), type || 'checking', initial, initial,
      parseBool(active) === false ? 0 : 1,
      family_id || null, parseBool(shared) ? 1 : 0,
      currency || req.user.currency || 'BRL',
    ]
  );

  const [rows] = await db.query('SELECT * FROM accounts WHERE id = ?', [result.insertId]);
  await audit(req.userId, 'account', result.insertId, 'create', rows[0]);
  res.status(201).json(rows[0]);
}));

// PUT /:id — atualiza dados da conta.
router.put('/:id', asyncHandler(async (req, res) => {
  const before = await loadOwnAccount(req.userId, req.params.id);
  const { name, type, currency, active, family_id, shared, initial_balance } = req.body;

  if (type && !ACCOUNT_TYPES.includes(type)) throw badRequest(`Tipo de conta inválido. Use: ${ACCOUNT_TYPES.join(', ')}.`);
  if (family_id) await scope.assertCanUseFamily(req.userId, family_id);

  const nextInitial = initial_balance === undefined || initial_balance === null
    ? Number(before.initial_balance || 0)
    : Number(initial_balance);
  if (Number.isNaN(nextInitial)) throw badRequest('Saldo inicial inválido.');

  // Mudar o saldo inicial desloca o saldo atual pela mesma diferença.
  const diff = nextInitial - Number(before.initial_balance || 0);

  await db.query(
    `UPDATE accounts SET
       name = ?, type = ?, currency = ?, active = ?, family_id = ?, shared = ?,
       initial_balance = ?, current_balance = current_balance + ?
     WHERE id = ? AND user_id = ?`,
    [
      name === undefined ? before.name : String(name).trim(),
      type === undefined ? before.type : type,
      currency === undefined ? before.currency : currency,
      active === undefined ? before.active : (parseBool(active) ? 1 : 0),
      family_id === undefined ? before.family_id : (family_id || null),
      shared === undefined ? before.shared : (parseBool(shared) ? 1 : 0),
      nextInitial, diff, before.id, req.userId,
    ]
  );

  const [rows] = await db.query('SELECT * FROM accounts WHERE id = ?', [before.id]);
  await audit(req.userId, 'account', before.id, 'update', { before, after: rows[0], balance_shift: diff });
  res.json(rows[0]);
}));

// POST /:id/adjust — ajuste de saldo (spec §3). O valor pode ser negativo.
router.post('/:id/adjust', asyncHandler(async (req, res) => {
  const account = await loadOwnAccount(req.userId, req.params.id);
  const { amount, description, date } = req.body;
  if (amount === undefined || amount === null || Number(amount) === 0 || Number.isNaN(Number(amount))) {
    throw badRequest('Informe um valor de ajuste diferente de zero.');
  }

  const transaction = await withTransaction(conn => ledger.createTransaction(conn, req.userId, {
    account_id: account.id,
    type: 'adjustment',
    amount: Number(amount),
    date: date || dates.toIsoDate(new Date()),
    description: description || 'Ajuste de saldo',
    currency: account.currency,
    family_id: account.family_id || null,
    source: 'manual',
  }));

  await audit(req.userId, 'account', account.id, 'update', { adjust: Number(amount), transaction_id: transaction.id });
  res.status(201).json(transaction);
}));

// POST /:id/deposit — entrada de dinheiro na conta.
router.post('/:id/deposit', asyncHandler(async (req, res) => {
  res.status(201).json(await moveMoney(req, 'income'));
}));

// POST /:id/withdraw — saída de dinheiro da conta.
router.post('/:id/withdraw', asyncHandler(async (req, res) => {
  res.status(201).json(await moveMoney(req, 'expense'));
}));

async function moveMoney(req, type) {
  const account = await loadOwnAccount(req.userId, req.params.id);
  const { amount, category_id, description, date } = req.body;
  const value = Number(amount);
  if (!value || Number.isNaN(value) || value <= 0) throw badRequest('Informe um valor maior que zero.');

  if (category_id) {
    const [categories] = await db.query(
      'SELECT id FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL)',
      [category_id, req.userId]
    );
    if (categories.length === 0) throw Object.assign(new Error('Categoria não encontrada.'), { status: 404 });
  }

  const transaction = await withTransaction(conn => ledger.createTransaction(conn, req.userId, {
    account_id: account.id,
    category_id: category_id || null,
    type,
    amount: value,
    date: date || dates.toIsoDate(new Date()),
    description: description || (type === 'income' ? 'Depósito' : 'Retirada'),
    currency: account.currency,
    family_id: account.family_id || null,
    source: 'manual',
  }));

  await audit(req.userId, 'transaction', transaction.id, 'create', { origin: type === 'income' ? 'deposit' : 'withdraw' });
  return transaction;
}

// DELETE /:id — bloqueia exclusão quando há histórico vinculado.
router.delete('/:id', asyncHandler(async (req, res) => {
  const account = await loadOwnAccount(req.userId, req.params.id);

  const [counts] = await db.query(
    'SELECT COUNT(*) AS total FROM transactions WHERE account_id = ? OR transfer_account_id = ?',
    [account.id, account.id]
  );
  const total = Number(counts[0]?.total || 0);
  if (total > 0) {
    throw Object.assign(
      new Error(`Esta conta possui ${total} lançamento(s) vinculado(s) e não pode ser excluída. Desative a conta para preservar o histórico.`),
      { status: 409 }
    );
  }

  await db.query('DELETE FROM accounts WHERE id = ? AND user_id = ?', [account.id, req.userId]);
  await audit(req.userId, 'account', account.id, 'delete', account);
  res.json({ message: 'Conta excluída.' });
}));

module.exports = router;
