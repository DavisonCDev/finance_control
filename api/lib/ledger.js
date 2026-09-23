// Motor de lançamentos: centraliza o efeito de cada transação sobre saldos,
// faturas de cartão e transferências (spec §3, §4, §5, §25).
//
// Modelo de transferência: um único registro com account_id (origem) e
// transfer_account_id (destino). Transferências nunca entram como receita/despesa
// nos relatórios — quem consulta filtra `type <> 'transfer'`.
const { invoicePeriodFor } = require('./dates');
const { ensureBudget, ensureBudgetForTransaction } = require('../services/autoBudget');

const BALANCE_SIGN = { income: 1, expense: -1, adjustment: 1 };

async function ensureInvoice(conn, userId, cardId, date) {
  const [cards] = await conn.query(
    'SELECT id, closing_day, due_day FROM credit_cards WHERE id = ? AND user_id = ?',
    [cardId, userId]
  );
  if (cards.length === 0) {
    const error = new Error('Cartão não encontrado.');
    error.status = 404;
    throw error;
  }

  const card = cards[0];
  const period = invoicePeriodFor(date, card.closing_day || 1, card.due_day || 10);

  const [existing] = await conn.query(
    'SELECT * FROM card_invoices WHERE card_id = ? AND reference_month = ?',
    [cardId, period.referenceMonth]
  );
  if (existing.length > 0) return existing[0];

  const [result] = await conn.query(
    `INSERT INTO card_invoices (user_id, card_id, reference_month, closing_date, due_date)
     VALUES (?, ?, ?, ?, ?)`,
    [userId, cardId, period.referenceMonth, period.closingDate, period.dueDate]
  );
  const [rows] = await conn.query('SELECT * FROM card_invoices WHERE id = ?', [result.insertId]);
  return rows[0];
}

async function refreshInvoiceTotal(conn, invoiceId) {
  await conn.query(
    `UPDATE card_invoices i
     SET i.total_amount = COALESCE((
       SELECT SUM(CASE WHEN t.is_refund THEN -t.amount ELSE t.amount END)
       FROM transactions t
       WHERE t.invoice_id = i.id AND t.deleted_at IS NULL
     ), 0)
     WHERE i.id = ?`,
    [invoiceId]
  );
  await conn.query(
    `UPDATE card_invoices
     SET status = CASE
       WHEN paid_amount >= total_amount AND total_amount > 0 THEN 'paid'
       WHEN paid_amount > 0 THEN 'partial'
       WHEN closing_date <= CURDATE() THEN 'closed'
       ELSE 'open'
     END
     WHERE id = ?`,
    [invoiceId]
  );
}

/**
 * Aplica (direction = 1) ou reverte (direction = -1) o efeito de um lançamento.
 * `tx` precisa conter: type, amount, account_id, card_id, invoice_id,
 * transfer_account_id, is_refund.
 */
async function applyEffect(conn, tx, direction) {
  const amount = Number(tx.amount) * direction;

  if (tx.type === 'transfer') {
    if (tx.account_id) {
      await conn.query('UPDATE accounts SET current_balance = current_balance - ? WHERE id = ?', [amount, tx.account_id]);
    }
    if (tx.transfer_account_id) {
      await conn.query('UPDATE accounts SET current_balance = current_balance + ? WHERE id = ?', [amount, tx.transfer_account_id]);
    }
    return;
  }

  // Compra no cartão não mexe em saldo de conta: entra na fatura.
  if (tx.card_id) {
    if (tx.invoice_id) await refreshInvoiceTotal(conn, tx.invoice_id);
    return;
  }

  const sign = BALANCE_SIGN[tx.type];
  if (sign && tx.account_id) {
    await conn.query('UPDATE accounts SET current_balance = current_balance + ? WHERE id = ?', [amount * sign, tx.account_id]);
  }
}

/**
 * Cria um lançamento já com todos os efeitos colaterais.
 * Retorna a linha inserida (com joins de nome).
 */
async function createTransaction(conn, userId, payload) {
  const {
    account_id = null,
    category_id = null,
    card_id = null,
    type,
    amount,
    date,
    time = null,
    description = null,
    notes = null,
    family_id = null,
    person_id = null,
    location = null,
    latitude = null,
    longitude = null,
    currency = 'BRL',
    original_amount = null,
    exchange_rate = null,
    status = 'cleared',
    transfer_account_id = null,
    transfer_to_user_id = null,
    installment_id = null,
    installment_number = null,
    recurring_id = null,
    goal_id = null,
    investment_id = null,
    debt_id = null,
    import_hash = null,
    client_uuid = null,
    source = 'manual',
    is_refund = false,
    tagIds = [],
    accrual_date = null,
    payment_date = null,
    is_paid = null,
    payment_method = 'OTHER',
    cost_center_id = null,
    contact_id = null,
    classification = null,
    pc_reference = null,
    item = null,
  } = payload;

  const normalizedAccrual = accrual_date || date;
  const normalizedPayment = payment_date || date;
  const normalizedPaid = is_paid !== null ? is_paid : (status !== 'scheduled' && status !== 'cancelled');

  if (!type || amount === undefined || amount === null || !date) {
    const error = new Error('Tipo, valor e data são obrigatórios.');
    error.status = 400;
    throw error;
  }
  if (type === 'transfer' && !transfer_account_id) {
    const error = new Error('Transferência exige a conta de destino.');
    error.status = 400;
    throw error;
  }
  if (type === 'transfer' && Number(transfer_account_id) === Number(account_id)) {
    const error = new Error('Conta de origem e destino devem ser diferentes.');
    error.status = 400;
    throw error;
  }

  let invoice = null;
  if (card_id) invoice = await ensureInvoice(conn, userId, card_id, date);

  const [result] = await conn.query(
    `INSERT INTO transactions (
       user_id, account_id, category_id, card_id, invoice_id, type, amount, date, time,
       description, notes, family_id, person_id, location, latitude, longitude, currency,
       original_amount, exchange_rate, status, transfer_account_id, transfer_to_user_id,
       installment_id, installment_number, recurring_id, goal_id, investment_id, debt_id,
       import_hash, client_uuid, source, is_refund,
       accrual_date, payment_date, is_paid, payment_method, cost_center_id, contact_id,
       classification, pc_reference, item
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      userId, account_id, category_id, card_id, invoice?.id || null, type, amount, date, time,
      description, notes, family_id, person_id || userId, location, latitude, longitude, currency,
      original_amount, exchange_rate, status, transfer_account_id, transfer_to_user_id,
      installment_id, installment_number, recurring_id, goal_id, investment_id, debt_id,
      import_hash, client_uuid, source, is_refund ? 1 : 0,
      normalizedAccrual, normalizedPayment, normalizedPaid, payment_method, cost_center_id, contact_id,
      classification, pc_reference, item,
    ]
  );

  const transactionId = result.insertId;

  for (const tagId of tagIds.filter(Boolean)) {
    await conn.query('INSERT IGNORE INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)', [transactionId, tagId]);
  }

  if (status !== 'cancelled' && status !== 'scheduled' && normalizedPaid) {
    await applyEffect(conn, {
      type, amount, account_id, card_id, invoice_id: invoice?.id || null,
      transfer_account_id, is_refund,
    }, 1);
  } else if (invoice) {
    // Compra no cartao marca is_paid=false (só vira caixa no pagamento da
    // fatura), mas a fatura precisa ser recalculada mesmo assim.
    await refreshInvoiceTotal(conn, invoice.id);
  }

  await ensureBudgetForTransaction(userId, {
    type, category_id: category_id, amount, accrual_date: normalizedAccrual,
    date, recurring_id, card_id, source,
  }, conn);

  return findTransaction(conn, transactionId);
}

async function deleteTransaction(conn, userId, transactionId) {
  const [rows] = await conn.query(
    'SELECT * FROM transactions WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
    [transactionId, userId]
  );
  if (rows.length === 0) {
    const error = new Error('Transação não encontrada.');
    error.status = 404;
    throw error;
  }

  const tx = rows[0];
  await conn.query('DELETE FROM transactions WHERE id = ?', [transactionId]);

  if (tx.status !== 'cancelled' && tx.status !== 'scheduled' && tx.is_paid) {
    await applyEffect(conn, tx, -1);
  }

  if (tx.type === 'expense' && tx.category_id && !tx.recurring_id && !tx.card_id && tx.source !== 'invoice_payment') {
    const month = String(tx.accrual_date || tx.date).slice(0, 7);
    if (/^\d{4}-\d{2}$/.test(month)) {
      await ensureBudget(userId, tx.category_id, month, -Number(tx.amount || 0), conn);
    }
  }

  if (tx.invoice_id) await refreshInvoiceTotal(conn, tx.invoice_id);
  if (tx.installment_id) {
    await conn.query(
      'UPDATE installment_items SET paid = FALSE, paid_at = NULL, transaction_id = NULL WHERE transaction_id = ?',
      [transactionId]
    );
    await syncInstallmentProgress(conn, tx.installment_id);
  }

  return tx;
}

async function updateTransaction(conn, userId, transactionId, payload) {
  const [rows] = await conn.query(
    'SELECT * FROM transactions WHERE id = ? AND user_id = ? AND deleted_at IS NULL',
    [transactionId, userId]
  );
  if (rows.length === 0) {
    const error = new Error('Transação não encontrada.');
    error.status = 404;
    throw error;
  }

  const before = rows[0];
  if (before.status !== 'cancelled' && before.status !== 'scheduled' && before.is_paid) {
    await applyEffect(conn, before, -1);
  }

  const merged = {
    account_id: pick(payload.account_id, before.account_id),
    category_id: pick(payload.category_id, before.category_id),
    card_id: pick(payload.card_id, before.card_id),
    type: pick(payload.type, before.type),
    amount: pick(payload.amount, before.amount),
    date: pick(payload.date, before.date),
    time: pick(payload.time, before.time),
    description: pick(payload.description, before.description),
    notes: pick(payload.notes, before.notes),
    family_id: pick(payload.family_id, before.family_id),
    person_id: pick(payload.person_id, before.person_id),
    location: pick(payload.location, before.location),
    currency: pick(payload.currency, before.currency),
    status: pick(payload.status, before.status),
    transfer_account_id: pick(payload.transfer_account_id, before.transfer_account_id),
    goal_id: pick(payload.goal_id, before.goal_id),
    is_refund: pick(payload.is_refund, before.is_refund),
    source: pick(payload.source, before.source),
    accrual_date: pick(payload.accrual_date, before.accrual_date) || before.date,
    payment_date: pick(payload.payment_date, before.payment_date) || before.date,
    is_paid: pick(payload.is_paid, before.is_paid),
    payment_method: pick(payload.payment_method, before.payment_method) || 'OTHER',
    cost_center_id: pick(payload.cost_center_id, before.cost_center_id),
    contact_id: pick(payload.contact_id, before.contact_id),
    classification: pick(payload.classification, before.classification),
    pc_reference: pick(payload.pc_reference, before.pc_reference),
    item: pick(payload.item, before.item),
  };

  let invoiceId = before.invoice_id;
  if (merged.card_id) {
    const invoice = await ensureInvoice(conn, userId, merged.card_id, merged.date);
    invoiceId = invoice.id;
  } else {
    invoiceId = null;
  }

  await conn.query(
    `UPDATE transactions SET
       account_id = ?, category_id = ?, card_id = ?, invoice_id = ?, type = ?, amount = ?,
       date = ?, time = ?, description = ?, notes = ?, family_id = ?, person_id = ?,
       location = ?, currency = ?, status = ?, transfer_account_id = ?, goal_id = ?, is_refund = ?,
       accrual_date = ?, payment_date = ?, is_paid = ?, payment_method = ?, cost_center_id = ?, contact_id = ?,
       classification = ?, pc_reference = ?, item = ?
     WHERE id = ? AND user_id = ?`,
    [
      merged.account_id, merged.category_id, merged.card_id, invoiceId, merged.type, merged.amount,
      merged.date, merged.time, merged.description, merged.notes, merged.family_id, merged.person_id,
      merged.location, merged.currency, merged.status, merged.transfer_account_id, merged.goal_id,
      merged.is_refund ? 1 : 0,
      merged.accrual_date, merged.payment_date, merged.is_paid, merged.payment_method,
      merged.cost_center_id, merged.contact_id,
      merged.classification, merged.pc_reference, merged.item,
      transactionId, userId,
    ]
  );

  if (Array.isArray(payload.tagIds)) {
    await conn.query('DELETE FROM transaction_tags WHERE transaction_id = ?', [transactionId]);
    for (const tagId of payload.tagIds.filter(Boolean)) {
      await conn.query('INSERT IGNORE INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)', [transactionId, tagId]);
    }
  }

  if (merged.status !== 'cancelled' && merged.status !== 'scheduled' && merged.is_paid) {
    await applyEffect(conn, { ...merged, invoice_id: invoiceId }, 1);
  }
  if (before.invoice_id && before.invoice_id !== invoiceId) await refreshInvoiceTotal(conn, before.invoice_id);

  // Ajuste de previsao: desfaz a contribuicao anterior e aplica a nova.
  // Transacoes de recorrencia e de cartao nao contribuem para a previsao.
  const validMonth = (m) => /^\d{4}-\d{2}$/.test(m);
  const beforeMonth = String(before.accrual_date || before.date).slice(0, 7);
  const afterMonth = String(merged.accrual_date || merged.date).slice(0, 7);
  const beforeContrib =
    before.type === 'expense' && before.category_id && !before.recurring_id && !before.card_id && before.source !== 'invoice_payment'
      ? Number(before.amount || 0) : 0;
  const afterContrib =
    merged.type === 'expense' && merged.category_id && !before.recurring_id && !merged.card_id && merged.source !== 'invoice_payment'
      ? Number(merged.amount || 0) : 0;

  if (beforeContrib || afterContrib) {
    if (before.category_id === merged.category_id && beforeMonth === afterMonth && validMonth(afterMonth)) {
      const diff = afterContrib - beforeContrib;
      if (diff) await ensureBudget(userId, merged.category_id, afterMonth, diff, conn);
    } else {
      if (beforeContrib && validMonth(beforeMonth)) {
        await ensureBudget(userId, before.category_id, beforeMonth, -beforeContrib, conn);
      }
      if (afterContrib && validMonth(afterMonth)) {
        await ensureBudget(userId, merged.category_id, afterMonth, afterContrib, conn);
      }
    }
  }

  return findTransaction(conn, transactionId);
}

async function syncInstallmentProgress(conn, installmentId) {
  await conn.query(
    `UPDATE installments i SET
       i.paid_installments = COALESCE((SELECT COUNT(*) FROM installment_items WHERE installment_id = i.id AND paid = TRUE), 0),
       i.current_installment = LEAST(i.total_installments, COALESCE((SELECT COUNT(*) FROM installment_items WHERE installment_id = i.id AND paid = TRUE), 0) + 1)
     WHERE i.id = ?`,
    [installmentId]
  );
  await conn.query(
    `UPDATE installments i SET i.status = 'completed', i.active = FALSE
     WHERE i.id = ? AND i.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM installment_items WHERE installment_id = i.id AND paid = FALSE AND cancelled = FALSE)`,
    [installmentId]
  );
}

const TRANSACTION_SELECT = `
  SELECT t.*,
         c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
         parent.name AS category_parent_name,
         a.name AS account_name,
         dest.name AS transfer_account_name,
         cc.name AS card_name, cc.color AS card_color,
         u.name AS person_name,
         f.name AS family_name,
         ctr.name AS cost_center_name,
         ct.name AS contact_name,
         (SELECT GROUP_CONCAT(tg.name) FROM transaction_tags tt JOIN tags tg ON tg.id = tt.tag_id WHERE tt.transaction_id = t.id) AS tag_names,
         (SELECT COUNT(*) FROM attachments at WHERE at.transaction_id = t.id) AS attachment_count
  FROM transactions t
  LEFT JOIN categories c ON t.category_id = c.id
  LEFT JOIN categories parent ON c.parent_id = parent.id
  LEFT JOIN accounts a ON t.account_id = a.id
  LEFT JOIN accounts dest ON t.transfer_account_id = dest.id
  LEFT JOIN credit_cards cc ON t.card_id = cc.id
  LEFT JOIN users u ON t.person_id = u.id
  LEFT JOIN families f ON t.family_id = f.id
  LEFT JOIN cost_centers ctr ON t.cost_center_id = ctr.id
  LEFT JOIN contacts ct ON t.contact_id = ct.id
`;

async function findTransaction(conn, transactionId) {
  const [rows] = await conn.query(`${TRANSACTION_SELECT} WHERE t.id = ?`, [transactionId]);
  return rows[0];
}

function pick(value, fallback) {
  return value === undefined ? fallback : value;
}

module.exports = {
  ensureInvoice,
  refreshInvoiceTotal,
  applyEffect,
  createTransaction,
  updateTransaction,
  deleteTransaction,
  findTransaction,
  syncInstallmentProgress,
  TRANSACTION_SELECT,
};
