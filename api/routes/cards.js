// Cartões de crédito, faturas, compras parceladas e pagamento de fatura (spec §4).
//
// Regra central: compra no cartão não mexe em saldo de conta — ela entra na
// fatura do período correto. Quem debita a conta é o pagamento da fatura.
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const { notify } = require('../lib/notify');
const dates = require('../lib/dates');
const ledger = require('../lib/ledger');
const scope = require('../lib/scope');

const router = express.Router();
router.use(authenticate);

const UNPAID_STATUS = ['open', 'closed', 'partial'];

function fail(message, status = 400) {
  return Object.assign(new Error(message), { status });
}

function round2(value) {
  return Math.round(Number(value) * 100) / 100;
}

// Divide o total em N parcelas de 2 casas, jogando a sobra de arredondamento
// na última parcela para que a soma feche exatamente com o valor da compra.
function splitAmount(total, count) {
  const base = round2(Number(total) / count);
  const parts = new Array(count).fill(base);
  parts[count - 1] = round2(Number(total) - base * (count - 1));
  return parts;
}

async function findCard(userId, cardId) {
  const [rows] = await db.query('SELECT * FROM credit_cards WHERE id = ? AND user_id = ?', [cardId, userId]);
  if (rows.length === 0) throw fail('Cartão não encontrado.', 404);
  return rows[0];
}

async function findInvoice(userId, invoiceId) {
  const [rows] = await db.query(
    `SELECT i.*, c.name AS card_name FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE i.id = ? AND i.user_id = ?`,
    [invoiceId, userId]
  );
  if (rows.length === 0) throw fail('Fatura não encontrada.', 404);
  return rows[0];
}

function withRemaining(invoice) {
  return { ...invoice, remaining: round2(Number(invoice.total_amount || 0) - Number(invoice.paid_amount || 0)) };
}

function readCardBody(body) {
  const {
    name, bank, brand, limit_amount, closing_day, due_day, holder_name, last_digits,
    color, currency, family_id, shared, default_account_id, parent_card_id, is_additional,
  } = body;

  if (closing_day !== undefined && closing_day !== null && (closing_day < 1 || closing_day > 31)) {
    throw fail('Dia de fechamento deve estar entre 1 e 31.');
  }
  if (due_day !== undefined && due_day !== null && (due_day < 1 || due_day > 31)) {
    throw fail('Dia de vencimento deve estar entre 1 e 31.');
  }
  if (last_digits !== undefined && last_digits !== null && last_digits !== '' && !/^\d{4}$/.test(String(last_digits))) {
    throw fail('Os últimos dígitos devem ter exatamente 4 números.');
  }

  return {
    name, bank, brand, limit_amount, closing_day, due_day, holder_name, last_digits,
    color, currency, family_id, shared, default_account_id, parent_card_id, is_additional,
  };
}

// ------------------------------------------------------------------- listagem

router.get('/', asyncHandler(async (req, res) => {
  const visible = await scope.visibilityClause(req.userId, 'c');
  const [cards] = await db.query(
    `SELECT c.*,
            COALESCE((
              SELECT SUM(i.total_amount - i.paid_amount) FROM card_invoices i
              WHERE i.card_id = c.id AND i.status IN ('open','closed','partial')
            ), 0) AS used_limit,
            COALESCE((
              SELECT SUM(CASE WHEN t.is_refund THEN -t.amount ELSE t.amount END) FROM transactions t
              WHERE t.card_id = c.id AND t.deleted_at IS NULL AND t.date > CURDATE()
            ), 0) AS future_purchases_total
     FROM credit_cards c
     WHERE ${visible.sql}
     ORDER BY c.name`,
    visible.params
  );

  const ids = cards.map(c => c.id);
  let additional = [];
  if (ids.length > 0) {
    const [rows] = await db.query(
      `SELECT * FROM credit_cards WHERE parent_card_id IN (${ids.map(() => '?').join(',')}) ORDER BY name`,
      ids
    );
    additional = rows;
  }

  const result = [];
  for (const card of cards) {
    // A fatura corrente já entra em used_limit (status 'open'), por isso as
    // compras dela não são somadas de novo aqui — evita limite usado dobrado.
    const period = dates.invoicePeriodFor(dates.toIsoDate(new Date()), card.closing_day || 1, card.due_day || 10);
    const [invoices] = await db.query(
      'SELECT id, reference_month, total_amount, paid_amount, due_date, closing_date, status FROM card_invoices WHERE card_id = ? AND reference_month = ?',
      [card.id, period.referenceMonth]
    );

    const currentInvoice = invoices[0]
      ? withRemaining(invoices[0])
      : {
          id: null,
          reference_month: period.referenceMonth,
          total_amount: 0,
          paid_amount: 0,
          due_date: period.dueDate,
          closing_date: period.closingDate,
          status: 'open',
          remaining: 0,
        };

    const usedLimit = round2(card.used_limit);
    result.push({
      ...card,
      used_limit: usedLimit,
      available_limit: round2(Number(card.limit_amount || 0) - usedLimit),
      future_purchases_total: round2(card.future_purchases_total),
      current_invoice: currentInvoice,
      additional_cards: additional.filter(a => a.parent_card_id === card.id),
    });
  }

  res.json(result);
}));

// -------------------------------------------------------- faturas (rotas fixas)

// GET /invoices — todas as faturas do usuario, por data de vencimento.
router.get('/invoices', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    `SELECT i.*, c.name AS card_name, c.color AS card_color, c.brand
     FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE i.user_id = ? AND i.status <> 'cancelled'
     ORDER BY i.due_date DESC`,
    [req.userId]
  );
  res.json(rows.map(withRemaining));
}));

router.get('/invoices/upcoming', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    `SELECT i.*, c.name AS card_name, c.color AS card_color, c.brand
     FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE i.user_id = ? AND i.status <> 'paid'
       AND i.due_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)
     ORDER BY i.due_date`,
    [req.userId]
  );
  res.json(rows.map(withRemaining));
}));

async function ensurePaymentCategory(conn, userId, name = 'Cartão de crédito') {
  const [rows] = await conn.query(
    'SELECT id FROM categories WHERE user_id = ? AND name = ? AND type = ? LIMIT 1',
    [userId, name, 'expense']
  );
  if (rows.length > 0) return rows[0].id;
  const [inserted] = await conn.query(
    'INSERT INTO categories (user_id, name, type, color) VALUES (?, ?, ?, ?)',
    [userId, name, 'expense', '#E53935']
  );
  return inserted.insertId;
}

router.post('/invoices/:invoiceId/pay', asyncHandler(async (req, res) => {
  const { account_id, amount, date, category_id } = req.body;
  if (!account_id) throw fail('Informe a conta usada no pagamento.');

  const payload = await withTransaction(async conn => {
    const [invoices] = await conn.query(
      `SELECT i.*, c.name AS card_name FROM card_invoices i
       JOIN credit_cards c ON c.id = i.card_id
       WHERE i.id = ? AND i.user_id = ?`,
      [req.params.invoiceId, req.userId]
    );
    if (invoices.length === 0) throw fail('Fatura não encontrada.', 404);
    const invoice = invoices[0];

    const [accounts] = await conn.query('SELECT id, name FROM accounts WHERE id = ? AND user_id = ?', [account_id, req.userId]);
    if (accounts.length === 0) throw fail('Conta não encontrada.', 404);

    const remaining = round2(Number(invoice.total_amount) - Number(invoice.paid_amount));
    if (remaining <= 0) throw fail('Esta fatura já está paga.');

    const value = amount === undefined || amount === null || amount === '' ? remaining : round2(amount);
    if (value <= 0) throw fail('O valor do pagamento deve ser maior que zero.');
    if (value > remaining) {
      throw fail(`Valor acima do saldo da fatura. Restam R$ ${remaining.toFixed(2)} a pagar.`);
    }

    const paidAt = date || dates.toIsoDate(new Date());

    const paymentCategoryId = category_id || await ensurePaymentCategory(conn, req.userId);

    // Sem card_id: o pagamento debita o saldo da conta, não entra na fatura.
    const transaction = await ledger.createTransaction(conn, req.userId, {
      account_id,
      category_id: paymentCategoryId,
      type: 'expense',
      amount: value,
      date: paidAt,
      description: `Pagamento fatura ${invoice.card_name} ${invoice.reference_month}`,
      source: 'invoice_payment',
    });

    await conn.query(
      'INSERT INTO invoice_payments (invoice_id, account_id, transaction_id, amount, paid_at) VALUES (?, ?, ?, ?, ?)',
      [invoice.id, account_id, transaction.id, value, paidAt]
    );

    const newPaid = round2(Number(invoice.paid_amount) + value);
    const status = newPaid >= Number(invoice.total_amount) ? 'paid' : 'partial';
    await conn.query(
      'UPDATE card_invoices SET paid_amount = ?, status = ?, paid_at = ?, updated_at = NOW() WHERE id = ?',
      [newPaid, status, status === 'paid' ? paidAt : invoice.paid_at, invoice.id]
    );

    const [updated] = await conn.query('SELECT * FROM card_invoices WHERE id = ?', [invoice.id]);
    return { invoice: withRemaining(updated[0]), transaction, amount_paid: value };
  });

  await audit(req.userId, 'card_invoice', Number(req.params.invoiceId), 'update', { pago: payload.amount_paid });
  res.status(201).json({ message: 'Pagamento de fatura registrado.', ...payload });
}));

router.post('/invoices/:invoiceId/close', asyncHandler(async (req, res) => {
  const invoice = await findInvoice(req.userId, req.params.invoiceId);
  if (invoice.status === 'paid') throw fail('Fatura já está paga.');

  await withTransaction(async conn => {
    // refresh primeiro: ele recalcula o status pela data de fechamento, então o
    // 'closed' manual precisa ser gravado depois para não ser sobrescrito.
    await ledger.refreshInvoiceTotal(conn, invoice.id);
    await conn.query(
      `UPDATE card_invoices SET status = 'closed', updated_at = NOW() WHERE id = ? AND status = 'open'`,
      [invoice.id]
    );
  });

  const [rows] = await db.query('SELECT * FROM card_invoices WHERE id = ?', [invoice.id]);
  await audit(req.userId, 'card_invoice', invoice.id, 'update', { status: 'closed' });
  await notify({
    userId: req.userId,
    type: 'invoice_closed',
    title: `Fatura fechada — ${invoice.card_name}`,
    message: `A fatura de ${invoice.reference_month} fechou em R$ ${Number(rows[0].total_amount).toFixed(2)}, com vencimento em ${rows[0].due_date}.`,
    severity: 'info',
    entity: 'card_invoice',
    entityId: invoice.id,
    dedupeKey: `invoice_closed:${invoice.id}`,
  });

  res.json({ message: 'Fatura fechada.', invoice: withRemaining(rows[0]) });
}));

// ------------------------------------------------------------- cartão (detalhe)

router.get('/:id', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const [invoices] = await db.query(
    'SELECT * FROM card_invoices WHERE card_id = ? ORDER BY reference_month DESC LIMIT 6',
    [card.id]
  );
  const [additional] = await db.query('SELECT * FROM credit_cards WHERE parent_card_id = ? ORDER BY name', [card.id]);
  const [used] = await db.query(
    `SELECT COALESCE(SUM(total_amount - paid_amount), 0) AS used_limit FROM card_invoices
     WHERE card_id = ? AND status IN ('open','closed','partial')`,
    [card.id]
  );

  const usedLimit = round2(used[0].used_limit);
  res.json({
    ...card,
    used_limit: usedLimit,
    available_limit: round2(Number(card.limit_amount || 0) - usedLimit),
    invoices: invoices.map(withRemaining),
    additional_cards: additional,
  });
}));

router.get('/:id/invoices', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const [rows] = await db.query(
    'SELECT * FROM card_invoices WHERE card_id = ? ORDER BY reference_month DESC',
    [card.id]
  );
  res.json(rows.map(withRemaining));
}));

router.get('/:id/invoices/current', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const today = dates.toIsoDate(new Date());

  const invoice = await withTransaction(async conn => {
    const created = await ledger.ensureInvoice(conn, req.userId, card.id, today);
    await ledger.refreshInvoiceTotal(conn, created.id);
    const [rows] = await conn.query('SELECT * FROM card_invoices WHERE id = ?', [created.id]);
    return rows[0];
  });

  const [transactions] = await db.query(
    `SELECT t.id, t.date, t.amount, t.description, t.is_refund, t.installment_number, t.installment_id,
            CASE WHEN p.name IS NULL THEN c.name ELSE CONCAT(p.name, ' › ', c.name) END AS category_name
     FROM transactions t
     LEFT JOIN categories c ON c.id = t.category_id
     LEFT JOIN categories p ON p.id = c.parent_id
     WHERE t.invoice_id = ? AND t.deleted_at IS NULL
     ORDER BY t.date, t.id`,
    [invoice.id]
  );

  res.json({ ...withRemaining(invoice), card_name: card.name, transactions });
}));

router.get('/:id/invoices/:reference_month', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const [rows] = await db.query(
    'SELECT * FROM card_invoices WHERE card_id = ? AND reference_month = ?',
    [card.id, req.params.reference_month]
  );
  if (rows.length === 0) throw fail('Fatura não encontrada para este mês.', 404);
  const invoice = rows[0];

  const [transactions] = await db.query(
    `SELECT t.id, t.date, t.amount, t.description, t.notes, t.is_refund, t.installment_id,
            t.installment_number, t.source,
            CASE WHEN p.name IS NULL THEN c.name ELSE CONCAT(p.name, ' › ', c.name) END AS category_name,
            c.color AS category_color
     FROM transactions t
     LEFT JOIN categories c ON c.id = t.category_id
     LEFT JOIN categories p ON p.id = c.parent_id
     WHERE t.invoice_id = ? AND t.deleted_at IS NULL
     ORDER BY t.date, t.id`,
    [invoice.id]
  );

  const [payments] = await db.query(
    `SELECT p.*, a.name AS account_name FROM invoice_payments p
     LEFT JOIN accounts a ON a.id = p.account_id
     WHERE p.invoice_id = ? ORDER BY p.paid_at`,
    [invoice.id]
  );

  res.json({ ...withRemaining(invoice), card_name: card.name, transactions, payments });
}));

// ----------------------------------------------------------- criar / atualizar

router.post('/', asyncHandler(async (req, res) => {
  const data = readCardBody(req.body);
  if (!data.name) throw fail('Nome do cartão é obrigatório.');
  if (data.family_id) await scope.assertCanUseFamily(req.userId, data.family_id);

  let isAdditional = data.is_additional ? 1 : 0;
  if (data.parent_card_id) {
    const parent = await findCard(req.userId, data.parent_card_id);
    if (parent.is_additional) throw fail('Um cartão adicional não pode ser titular de outro adicional.');
    isAdditional = 1; // vinculado a um titular: sempre adicional
  }

  const [result] = await db.query(
    `INSERT INTO credit_cards
       (user_id, name, bank, brand, limit_amount, closing_day, due_day, holder_name, last_digits,
        color, currency, family_id, shared, default_account_id, parent_card_id, is_additional)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      req.userId, data.name, data.bank || null, data.brand || null, data.limit_amount || 0,
      data.closing_day || null, data.due_day || null, data.holder_name || null, data.last_digits || null,
      data.color || '#1565C0', data.currency || 'BRL', data.family_id || null, data.shared ? 1 : 0,
      data.default_account_id || null, data.parent_card_id || null, isAdditional,
    ]
  );

  const [rows] = await db.query('SELECT * FROM credit_cards WHERE id = ?', [result.insertId]);
  await audit(req.userId, 'credit_card', result.insertId, 'create', rows[0]);
  res.status(201).json(rows[0]);
}));

router.put('/:id', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const data = readCardBody(req.body);
  if (data.family_id) await scope.assertCanUseFamily(req.userId, data.family_id);

  let parentId = data.parent_card_id === undefined ? card.parent_card_id : data.parent_card_id;
  let isAdditional = data.is_additional === undefined ? card.is_additional : (data.is_additional ? 1 : 0);
  if (parentId) {
    if (Number(parentId) === Number(card.id)) throw fail('Um cartão não pode ser adicional de si mesmo.');
    const parent = await findCard(req.userId, parentId);
    if (parent.is_additional) throw fail('Um cartão adicional não pode ser titular de outro adicional.');
    isAdditional = 1;
  }

  const pick = (value, fallback) => (value === undefined ? fallback : value);
  const merged = {
    name: pick(data.name, card.name),
    bank: pick(data.bank, card.bank),
    brand: pick(data.brand, card.brand),
    limit_amount: pick(data.limit_amount, card.limit_amount),
    closing_day: pick(data.closing_day, card.closing_day),
    due_day: pick(data.due_day, card.due_day),
    holder_name: pick(data.holder_name, card.holder_name),
    last_digits: pick(data.last_digits, card.last_digits),
    color: pick(data.color, card.color),
    currency: pick(data.currency, card.currency),
    family_id: pick(data.family_id, card.family_id),
    shared: pick(data.shared, card.shared) ? 1 : 0,
    default_account_id: pick(data.default_account_id, card.default_account_id),
    active: pick(req.body.active, card.active) ? 1 : 0,
  };

  await db.query(
    `UPDATE credit_cards SET name = ?, bank = ?, brand = ?, limit_amount = ?, closing_day = ?, due_day = ?,
       holder_name = ?, last_digits = ?, color = ?, currency = ?, family_id = ?, shared = ?,
       default_account_id = ?, parent_card_id = ?, is_additional = ?, active = ?
     WHERE id = ? AND user_id = ?`,
    [
      merged.name, merged.bank, merged.brand, merged.limit_amount, merged.closing_day, merged.due_day,
      merged.holder_name, merged.last_digits, merged.color, merged.currency, merged.family_id, merged.shared,
      merged.default_account_id, parentId || null, isAdditional, merged.active, card.id, req.userId,
    ]
  );

  const [rows] = await db.query('SELECT * FROM credit_cards WHERE id = ?', [card.id]);
  await audit(req.userId, 'credit_card', card.id, 'update', merged);
  res.json(rows[0]);
}));

router.delete('/:id', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const [additional] = await db.query('SELECT id, name FROM credit_cards WHERE parent_card_id = ?', [card.id]);
  const cardIds = [card.id, ...additional.map(a => a.id)];

  const [counts] = await db.query(
    `SELECT COUNT(*) AS total FROM transactions
     WHERE card_id IN (${cardIds.map(() => '?').join(',')}) AND deleted_at IS NULL`,
    cardIds
  );
  if (counts[0].total > 0) {
    throw fail(
      `Este cartão possui ${counts[0].total} lançamento(s) vinculado(s) e não pode ser excluído. Desative o cartão para deixar de usá-lo mantendo o histórico.`,
      409
    );
  }

  await withTransaction(async conn => {
    await conn.query(`DELETE FROM credit_cards WHERE id IN (${cardIds.map(() => '?').join(',')}) AND user_id = ?`, [...cardIds, req.userId]);
  });

  await audit(req.userId, 'credit_card', card.id, 'delete', { adicionais_removidos: additional.length });
  res.json({
    message: additional.length > 0
      ? `Cartão removido junto com ${additional.length} cartão(ões) adicional(is).`
      : 'Cartão removido.',
    removed_additional_cards: additional,
  });
}));

// ------------------------------------------------------- compras e estornos

router.post('/:id/purchases', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const {
    amount, date, category_id = null, description = null, notes = null, family_id = null,
    accrual_date = null, payment_date = null, is_paid = false,
    payment_method = 'CREDIT_CARD', cost_center_id = null, contact_id = null,
    classification = null, pc_reference = null, item = null,
  } = req.body;
  const count = Number(req.body.installments || 1);

  if (!amount || Number(amount) <= 0) throw fail('Informe o valor da compra.');
  if (!date) throw fail('Informe a data da compra.');
  if (!Number.isInteger(count) || count < 1 || count > 480) throw fail('Número de parcelas inválido.');
  if (family_id) await scope.assertCanUseFamily(req.userId, family_id);

  const extra = {
    accrual_date, payment_date, is_paid, payment_method,
    cost_center_id, contact_id, classification, pc_reference, item,
  };

  const result = await withTransaction(async conn => {
    if (count === 1) {
      const transaction = await ledger.createTransaction(conn, req.userId, {
        card_id: card.id,
        category_id,
        type: 'expense',
        amount: round2(amount),
        date,
        description,
        notes,
        family_id,
        source: 'manual',
        ...extra,
      });
      return { transaction, installment: null, items: [] };
    }

    const parts = splitAmount(amount, count);
    const [inserted] = await conn.query(
      `INSERT INTO installments
         (user_id, card_id, category_id, description, total_amount, total_installments,
          current_installment, paid_installments, amount, type, start_date, purchase_date, status, notes)
       VALUES (?, ?, ?, ?, ?, ?, 1, 0, ?, 'expense', ?, ?, 'active', ?)`,
      [req.userId, card.id, category_id, description, round2(amount), count, parts[0], date, date, notes]
    );
    const installmentId = inserted.insertId;

    const items = [];
    for (let index = 0; index < count; index++) {
      const number = index + 1;
      const dueDate = dates.toIsoDate(dates.addMonths(date, index));

      // A data da parcela decide a fatura: ensureInvoice (dentro do ledger)
      // resolve o período correto de cada mês.
      const transaction = await ledger.createTransaction(conn, req.userId, {
        card_id: card.id,
        category_id,
        type: 'expense',
        amount: parts[index],
        date: dueDate,
        description: `${description || 'Compra no cartão'} (${number}/${count})`,
        notes,
        family_id,
        installment_id: installmentId,
        installment_number: number,
        source: 'installment',
        ...extra,
        accrual_date: dueDate,
      });

      const [item] = await conn.query(
        'INSERT INTO installment_items (installment_id, number, due_date, amount, transaction_id) VALUES (?, ?, ?, ?, ?)',
        [installmentId, number, dueDate, parts[index], transaction.id]
      );
      items.push({ id: item.insertId, number, due_date: dueDate, amount: parts[index], transaction_id: transaction.id });
    }

    const [installments] = await conn.query('SELECT * FROM installments WHERE id = ?', [installmentId]);
    return { transaction: null, installment: installments[0], items };
  });

  await audit(req.userId, 'credit_card', card.id, 'create', { compra: round2(amount), parcelas: count });
  res.status(201).json({
    message: count > 1 ? `Compra parcelada em ${count}x lançada no cartão.` : 'Compra lançada no cartão.',
    ...result,
  });
}));

router.post('/:id/refunds', asyncHandler(async (req, res) => {
  const card = await findCard(req.userId, req.params.id);
  const { amount, date, description = null, category_id = null } = req.body;
  if (!amount || Number(amount) <= 0) throw fail('Informe o valor do estorno.');
  if (!date) throw fail('Informe a data do estorno.');

  // is_refund = TRUE: o ledger subtrai o valor do total da fatura.
  const transaction = await withTransaction(conn => ledger.createTransaction(conn, req.userId, {
    card_id: card.id,
    category_id,
    type: 'expense',
    amount: round2(amount),
    date,
    description: description || 'Estorno no cartão',
    is_refund: true,
    source: 'manual',
  }));

  await audit(req.userId, 'transaction', transaction.id, 'create', { estorno: round2(amount) });
  res.status(201).json({ message: 'Estorno lançado na fatura.', transaction });
}));

module.exports = router;
