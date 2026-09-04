// Rotinas em lote executadas pelo agendador ou sob demanda via API.
// Cobrem: recorrências (§6), faturas (§4), parcelas (§7), notificações (§14),
// insights e assinaturas (§22), patrimônio (§19) e automações (§35).
const db = require('../db');
const { withTransaction } = require('../db');
const ledger = require('./ledger');
const { notify } = require('./notify');
const dates = require('./dates');

const LOW_BALANCE_THRESHOLD = Number(process.env.LOW_BALANCE_THRESHOLD || 100);
const DUE_SOON_DAYS = Number(process.env.DUE_SOON_DAYS || 3);

function userFilter(userId, column = 'user_id') {
  return userId ? { sql: ` AND ${column} = ?`, params: [userId] } : { sql: '', params: [] };
}

// ---------------------------------------------------------------- recorrências

async function runDueRecurring(userId = null) {
  const filter = userFilter(userId, 'r.user_id');
  const today = dates.toIsoDate(new Date());

  const [recurrings] = await db.query(
    `SELECT r.* FROM recurring_transactions r
     WHERE r.active = TRUE AND r.auto_generate = TRUE AND r.next_date <= ?${filter.sql}`,
    [today, ...filter.params]
  );

  let generated = 0;

  for (const recurring of recurrings) {
    let current = recurring.next_date;
    let done = recurring.occurrences_done;
    let active = true;

    // Catch-up: gera todas as ocorrências atrasadas.
    while (active && current <= today) {
      if (recurring.end_date && current > recurring.end_date) { active = false; break; }
      if (recurring.occurrences && done >= recurring.occurrences) { active = false; break; }

      await withTransaction(conn => ledger.createTransaction(conn, recurring.user_id, {
        account_id: recurring.account_id,
        card_id: recurring.card_id,
        category_id: recurring.category_id,
        family_id: recurring.family_id,
        type: recurring.type,
        amount: recurring.amount,
        date: current,
        description: recurring.description,
        recurring_id: recurring.id,
        source: 'recurring',
      }));

      generated++;
      done++;
      current = dates.nextOccurrence(current, recurring.frequency);

      if (recurring.end_date && current > recurring.end_date) active = false;
      if (recurring.occurrences && done >= recurring.occurrences) active = false;
    }

    await db.query(
      'UPDATE recurring_transactions SET next_date = ?, occurrences_done = ?, active = ?, last_run_at = NOW() WHERE id = ?',
      [current, done, active, recurring.id]
    );
  }

  return { recurrings: recurrings.length, generated };
}

// -------------------------------------------------------------------- faturas

async function closeDueInvoices() {
  const [result] = await db.query(
    `UPDATE card_invoices SET status = 'closed'
     WHERE status = 'open' AND closing_date <= CURDATE()`
  );

  const [closed] = await db.query(
    `SELECT i.*, c.name AS card_name FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE i.status = 'closed' AND i.closing_date = CURDATE()`
  );

  for (const invoice of closed) {
    await notify({
      userId: invoice.user_id,
      type: 'invoice_closed',
      title: `Fatura fechada — ${invoice.card_name}`,
      message: `A fatura de ${invoice.reference_month} fechou em R$ ${Number(invoice.total_amount).toFixed(2)}, com vencimento em ${invoice.due_date}.`,
      severity: 'info',
      entity: 'card_invoice',
      entityId: invoice.id,
      dedupeKey: `invoice_closed:${invoice.id}`,
    });
  }

  return { closed: result.affectedRows, notified: closed.length };
}

async function markDueInstallments() {
  const [items] = await db.query(
    `SELECT ii.*, i.user_id, i.description, i.card_id
     FROM installment_items ii
     JOIN installments i ON i.id = ii.installment_id
     WHERE ii.paid = FALSE AND ii.cancelled = FALSE
       AND ii.due_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)
       AND i.status = 'active' AND i.card_id IS NULL`,
    [DUE_SOON_DAYS]
  );

  for (const item of items) {
    await notify({
      userId: item.user_id,
      type: 'installment_due',
      title: `Parcela ${item.number} de ${item.description || 'parcelamento'}`,
      message: `Parcela de R$ ${Number(item.amount).toFixed(2)} vence em ${item.due_date}.`,
      severity: 'warning',
      entity: 'installment_item',
      entityId: item.id,
      dedupeKey: `installment_due:${item.id}`,
    });
  }

  return { notified: items.length };
}

// --------------------------------------------------------------- notificações

async function scanNotifications(userId = null) {
  const created = {
    budget: 0, bills: 0, cards: 0, balance: 0, installments: 0, income: 0, family: 0,
  };
  const month = dates.currentMonth();

  // Orçamento próximo do limite / estourado
  const budgetFilter = userFilter(userId, 'b.user_id');
  const [budgets] = await db.query(
    `SELECT b.*, c.name AS category_name,
            COALESCE((
              SELECT SUM(t.amount) FROM transactions t
              WHERE t.user_id = b.user_id AND t.category_id = b.category_id
                AND t.type = 'expense' AND t.deleted_at IS NULL
                AND DATE_FORMAT(t.date, '%Y-%m') = b.budget_month
            ), 0) AS spent
     FROM budgets b
     JOIN categories c ON c.id = b.category_id
     WHERE b.budget_month = ?${budgetFilter.sql}`,
    [month, ...budgetFilter.params]
  );

  for (const budget of budgets) {
    const percent = budget.amount > 0 ? (budget.spent / budget.amount) * 100 : 0;

    if (percent >= 100) {
      const id = await notify({
        userId: budget.user_id,
        type: 'budget_over',
        title: `Orçamento estourado: ${budget.category_name}`,
        message: `Você gastou R$ ${Number(budget.spent).toFixed(2)} de R$ ${Number(budget.amount).toFixed(2)} (${percent.toFixed(0)}%).`,
        severity: 'critical',
        entity: 'budget',
        entityId: budget.id,
        dedupeKey: `budget_over:${budget.id}:${month}`,
      });
      if (id) {
        created.budget++;
        await db.query('UPDATE budgets SET notified_over_at = NOW() WHERE id = ?', [budget.id]);
      }
    } else if (percent >= budget.alert_threshold) {
      const id = await notify({
        userId: budget.user_id,
        type: 'budget_near',
        title: `Orçamento em ${percent.toFixed(0)}%: ${budget.category_name}`,
        message: `Restam R$ ${(budget.amount - budget.spent).toFixed(2)} do orçamento de ${budget.category_name} neste mês.`,
        severity: 'warning',
        entity: 'budget',
        entityId: budget.id,
        dedupeKey: `budget_near:${budget.id}:${month}`,
      });
      if (id) {
        created.budget++;
        await db.query('UPDATE budgets SET notified_near_at = NOW() WHERE id = ?', [budget.id]);
      }
    }
  }

  // Contas a vencer
  const eventFilter = userFilter(userId);
  const [events] = await db.query(
    `SELECT * FROM financial_events
     WHERE paid = FALSE AND event_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)${eventFilter.sql}`,
    [DUE_SOON_DAYS, ...eventFilter.params]
  );
  for (const event of events) {
    const id = await notify({
      userId: event.user_id,
      type: 'bill_due',
      title: `${event.title} vence em breve`,
      message: `Vencimento em ${event.event_date}${event.amount > 0 ? ` — R$ ${Number(event.amount).toFixed(2)}` : ''}.`,
      severity: 'warning',
      entity: 'financial_event',
      entityId: event.id,
      dedupeKey: `bill_due:${event.id}`,
    });
    if (id) created.bills++;
  }

  // Faturas de cartão a vencer
  const invoiceFilter = userFilter(userId, 'i.user_id');
  const [invoices] = await db.query(
    `SELECT i.*, c.name AS card_name FROM card_invoices i
     JOIN credit_cards c ON c.id = i.card_id
     WHERE i.status IN ('closed','partial','open')
       AND i.due_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL ? DAY)
       AND i.paid_amount < i.total_amount${invoiceFilter.sql}`,
    [DUE_SOON_DAYS, ...invoiceFilter.params]
  );
  for (const invoice of invoices) {
    const id = await notify({
      userId: invoice.user_id,
      type: 'card_due',
      title: `Fatura do ${invoice.card_name} vence em ${invoice.due_date}`,
      message: `Saldo a pagar: R$ ${(invoice.total_amount - invoice.paid_amount).toFixed(2)}.`,
      severity: 'critical',
      entity: 'card_invoice',
      entityId: invoice.id,
      dedupeKey: `card_due:${invoice.id}`,
    });
    if (id) created.cards++;
  }

  // Saldo baixo
  const accountFilter = userFilter(userId);
  const [accounts] = await db.query(
    `SELECT * FROM accounts
     WHERE active = TRUE AND type <> 'investment' AND current_balance < ?${accountFilter.sql}`,
    [LOW_BALANCE_THRESHOLD, ...accountFilter.params]
  );
  for (const account of accounts) {
    const id = await notify({
      userId: account.user_id,
      type: 'low_balance',
      title: `Saldo baixo em ${account.name}`,
      message: `Saldo atual de R$ ${Number(account.current_balance).toFixed(2)}.`,
      severity: account.current_balance < 0 ? 'critical' : 'warning',
      entity: 'account',
      entityId: account.id,
      dedupeKey: `low_balance:${account.id}:${dates.toIsoDate(new Date())}`,
    });
    if (id) created.balance++;
  }

  const installmentResult = await markDueInstallments();
  created.installments = installmentResult.notified;

  // Receita esperada não registrada
  const recurringFilter = userFilter(userId, 'r.user_id');
  const [missing] = await db.query(
    `SELECT r.* FROM recurring_transactions r
     WHERE r.active = TRUE AND r.type = 'income'
       AND r.next_date < DATE_SUB(CURDATE(), INTERVAL 2 DAY)
       AND NOT EXISTS (
         SELECT 1 FROM transactions t
         WHERE t.user_id = r.user_id AND t.type = 'income' AND t.deleted_at IS NULL
           AND t.amount BETWEEN r.amount * 0.9 AND r.amount * 1.1
           AND t.date BETWEEN DATE_SUB(r.next_date, INTERVAL 5 DAY) AND DATE_ADD(r.next_date, INTERVAL 10 DAY)
       )${recurringFilter.sql}`,
    recurringFilter.params
  );
  for (const recurring of missing) {
    const id = await notify({
      userId: recurring.user_id,
      type: 'income_missing',
      title: `Receita esperada não registrada`,
      message: `${recurring.description || 'Receita recorrente'} de R$ ${Number(recurring.amount).toFixed(2)} era esperada em ${recurring.next_date}.`,
      severity: 'warning',
      entity: 'recurring_transaction',
      entityId: recurring.id,
      dedupeKey: `income_missing:${recurring.id}:${recurring.next_date}`,
    });
    if (id) created.income++;
  }

  created.family = await scanFamilyNotifications(userId);
  return created;
}

async function scanFamilyNotifications(userId = null) {
  const filter = userId ? { sql: ' AND t.user_id = ?', params: [userId] } : { sql: '', params: [] };
  const [recent] = await db.query(
    `SELECT t.id, t.family_id, t.user_id, t.amount, t.description, u.name AS person_name,
            c.name AS category_name
     FROM transactions t
     JOIN users u ON u.id = t.user_id
     LEFT JOIN categories c ON c.id = t.category_id
     WHERE t.family_id IS NOT NULL AND t.type = 'expense' AND t.deleted_at IS NULL
       AND t.created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)${filter.sql}`,
    filter.params
  );

  let count = 0;
  for (const tx of recent) {
    const [members] = await db.query(
      'SELECT user_id FROM family_members WHERE family_id = ? AND user_id <> ?',
      [tx.family_id, tx.user_id]
    );
    for (const member of members) {
      const id = await notify({
        userId: member.user_id,
        type: 'family_expense',
        title: `${tx.person_name} registrou um gasto`,
        message: `${tx.description || tx.category_name || 'Despesa'} — R$ ${Number(tx.amount).toFixed(2)}.`,
        entity: 'transaction',
        entityId: tx.id,
        dedupeKey: `family_expense:${tx.id}:${member.user_id}`,
      });
      if (id) count++;
    }
  }
  return count;
}

// ------------------------------------------------- assinaturas e insights (IA)

async function detectSubscriptions(userId = null) {
  const filter = userFilter(userId);
  const [users] = await db.query(
    `SELECT DISTINCT user_id FROM transactions WHERE deleted_at IS NULL${filter.sql}`,
    filter.params
  );

  let detected = 0;

  for (const { user_id } of users) {
    const [rows] = await db.query(
      `SELECT description, amount, date, category_id FROM transactions
       WHERE user_id = ? AND type = 'expense' AND deleted_at IS NULL
         AND description IS NOT NULL AND description <> ''
         AND date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
       ORDER BY date`,
      [user_id]
    );

    const groups = new Map();
    for (const row of rows) {
      const key = merchantKey(row.description);
      if (!key) continue;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(row);
    }

    for (const [merchant, items] of groups) {
      if (items.length < 3) continue;

      const amounts = items.map(i => Number(i.amount));
      const average = amounts.reduce((a, b) => a + b, 0) / amounts.length;
      const spread = Math.max(...amounts) - Math.min(...amounts);
      // Assinatura tem valor estável: variação de até 15% da média.
      if (average > 0 && spread / average > 0.15) continue;

      const intervals = [];
      for (let i = 1; i < items.length; i++) intervals.push(dates.daysBetween(items[i - 1].date, items[i].date));
      const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
      if (avgInterval < 20 || avgInterval > 400) continue;

      await db.query(
        `INSERT INTO detected_subscriptions
           (user_id, merchant, average_amount, occurrences, first_seen, last_seen, interval_days, category_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           average_amount = VALUES(average_amount), occurrences = VALUES(occurrences),
           last_seen = VALUES(last_seen), interval_days = VALUES(interval_days)`,
        [
          user_id, merchant, average.toFixed(2), items.length,
          items[0].date, items[items.length - 1].date, Math.round(avgInterval),
          items[items.length - 1].category_id,
        ]
      );
      detected++;
    }
  }

  return { detected };
}

function merchantKey(description) {
  const clean = String(description)
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\d+/g, ' ')
    .replace(/[^a-z\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (clean.length < 3) return null;
  return clean.split(' ').slice(0, 3).join(' ');
}

async function generateInsights(userId = null) {
  const filter = userFilter(userId, 'id');
  const [users] = await db.query(`SELECT id FROM users WHERE deleted_at IS NULL${filter.sql}`, filter.params);

  let created = 0;
  const month = dates.currentMonth();
  const previous = dates.addMonthsToMonth(month, -1);

  for (const { id: uid } of users) {
    // Aumento anormal por categoria: mês atual vs média dos 3 anteriores
    const [spikes] = await db.query(
      `SELECT c.id, c.name,
              SUM(CASE WHEN DATE_FORMAT(t.date, '%Y-%m') = ? THEN t.amount ELSE 0 END) AS current_total,
              SUM(CASE WHEN DATE_FORMAT(t.date, '%Y-%m') <> ? THEN t.amount ELSE 0 END) / 3 AS average_total
       FROM transactions t
       JOIN categories c ON c.id = t.category_id
       WHERE t.user_id = ? AND t.type = 'expense' AND t.deleted_at IS NULL
         AND t.date >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 3 MONTH)
       GROUP BY c.id, c.name
       HAVING current_total > 0 AND average_total > 0 AND current_total > average_total * 1.4`,
      [month, month, uid]
    );

    for (const spike of spikes) {
      const variation = ((spike.current_total / spike.average_total - 1) * 100).toFixed(0);
      const id = await insight(uid, {
        type: 'spending_spike',
        title: `Gasto acima do normal em ${spike.name}`,
        message: `Você gastou R$ ${Number(spike.current_total).toFixed(2)} em ${spike.name} neste mês, ${variation}% acima da média dos últimos 3 meses (R$ ${Number(spike.average_total).toFixed(2)}).`,
        severity: 'warning',
        referenceMonth: month,
        data: { category_id: spike.id, current: spike.current_total, average: spike.average_total },
        dedupeKey: `spending_spike:${spike.id}:${month}`,
      });
      if (id) created++;
    }

    // Assinaturas ativas
    const [subs] = await db.query(
      'SELECT COUNT(*) n, SUM(average_amount) total FROM detected_subscriptions WHERE user_id = ? AND ignored = FALSE',
      [uid]
    );
    if (subs[0].n >= 3) {
      const id = await insight(uid, {
        type: 'subscription_detected',
        title: `${subs[0].n} assinaturas recorrentes identificadas`,
        message: `Elas somam cerca de R$ ${Number(subs[0].total || 0).toFixed(2)} por ciclo. Revise se todas ainda são usadas.`,
        referenceMonth: month,
        data: { count: subs[0].n, total: subs[0].total },
        dedupeKey: `subscriptions:${uid}:${month}`,
      });
      if (id) created++;
    }

    // Comparação com o mês anterior
    const [totals] = await db.query(
      `SELECT
         SUM(CASE WHEN DATE_FORMAT(date, '%Y-%m') = ? AND type = 'expense' THEN amount ELSE 0 END) AS current_expense,
         SUM(CASE WHEN DATE_FORMAT(date, '%Y-%m') = ? AND type = 'expense' THEN amount ELSE 0 END) AS previous_expense,
         SUM(CASE WHEN DATE_FORMAT(date, '%Y-%m') = ? AND type = 'income' THEN amount ELSE 0 END) AS current_income
       FROM transactions WHERE user_id = ? AND deleted_at IS NULL`,
      [month, previous, month, uid]
    );
    const t = totals[0];
    if (t.previous_expense > 0 && t.current_expense > 0) {
      const delta = ((t.current_expense / t.previous_expense - 1) * 100);
      if (Math.abs(delta) >= 15) {
        const id = await insight(uid, {
          type: 'comparison',
          title: delta > 0 ? 'Gastos subiram em relação ao mês passado' : 'Gastos caíram em relação ao mês passado',
          message: `Despesas de R$ ${Number(t.current_expense).toFixed(2)} contra R$ ${Number(t.previous_expense).toFixed(2)} no mês anterior (${delta > 0 ? '+' : ''}${delta.toFixed(0)}%).`,
          severity: delta > 0 ? 'warning' : 'info',
          referenceMonth: month,
          data: { current: t.current_expense, previous: t.previous_expense },
          dedupeKey: `comparison:${uid}:${month}`,
        });
        if (id) created++;
      }
    }

    // Sugestão de economia: maior categoria do mês
    const [top] = await db.query(
      `SELECT c.name, SUM(t.amount) total FROM transactions t
       JOIN categories c ON c.id = t.category_id
       WHERE t.user_id = ? AND t.type = 'expense' AND t.deleted_at IS NULL
         AND DATE_FORMAT(t.date, '%Y-%m') = ?
       GROUP BY c.name ORDER BY total DESC LIMIT 1`,
      [uid, month]
    );
    if (top.length > 0 && t.current_income > 0) {
      const share = (top[0].total / t.current_income) * 100;
      if (share >= 25) {
        const id = await insight(uid, {
          type: 'saving_suggestion',
          title: `${top[0].name} consome ${share.toFixed(0)}% da sua renda`,
          message: `Reduzir 10% dessa categoria liberaria R$ ${(top[0].total * 0.1).toFixed(2)} por mês para a sua reserva ou metas.`,
          referenceMonth: month,
          data: { category: top[0].name, total: top[0].total, share },
          dedupeKey: `saving_suggestion:${uid}:${month}`,
        });
        if (id) created++;
      }
    }

    // Previsão de saldo no fim do mês
    const forecast = await forecastMonthEnd(uid, month);
    if (forecast) {
      const id = await insight(uid, {
        type: 'balance_forecast',
        title: forecast.projected < 0 ? 'Projeção de saldo negativo neste mês' : 'Projeção de fechamento do mês',
        message: `Saldo atual de R$ ${forecast.current.toFixed(2)}. Considerando receitas e despesas previstas, o mês deve fechar em R$ ${forecast.projected.toFixed(2)}.`,
        severity: forecast.projected < 0 ? 'critical' : 'info',
        referenceMonth: month,
        data: forecast,
        dedupeKey: `balance_forecast:${uid}:${month}`,
      });
      if (id) created++;
    }
  }

  return { created };
}

async function insight(userId, { type, title, message, severity = 'info', referenceMonth = null, data = null, dedupeKey = null }) {
  try {
    const [result] = await db.query(
      `INSERT INTO insights (user_id, type, title, message, severity, reference_month, data, dedupe_key)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [userId, type, title, message, severity, referenceMonth, data ? JSON.stringify(data) : null, dedupeKey]
    );
    return result.insertId;
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') return null;
    throw err;
  }
}

async function forecastMonthEnd(userId, month) {
  const { end } = dates.monthRange(month);

  const [[balance]] = await db.query(
    `SELECT COALESCE(SUM(current_balance), 0) total FROM accounts
     WHERE user_id = ? AND active = TRUE AND type <> 'investment'`,
    [userId]
  );

  const [[pending]] = await db.query(
    `SELECT
       COALESCE(SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END), 0) AS income,
       COALESCE(SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END), 0) AS expense
     FROM recurring_transactions
     WHERE user_id = ? AND active = TRUE AND next_date BETWEEN CURDATE() AND ?`,
    [userId, end]
  );

  const [[events]] = await db.query(
    `SELECT COALESCE(SUM(amount), 0) total FROM financial_events
     WHERE user_id = ? AND paid = FALSE AND direction = 'expense'
       AND event_date BETWEEN CURDATE() AND ?`,
    [userId, end]
  );

  const [[invoices]] = await db.query(
    `SELECT COALESCE(SUM(total_amount - paid_amount), 0) total FROM card_invoices
     WHERE user_id = ? AND paid_amount < total_amount AND due_date BETWEEN CURDATE() AND ?`,
    [userId, end]
  );

  const current = Number(balance.total);
  const projected = current + Number(pending.income) - Number(pending.expense) - Number(events.total) - Number(invoices.total);

  return {
    current,
    expected_income: Number(pending.income),
    expected_expense: Number(pending.expense),
    pending_bills: Number(events.total),
    pending_invoices: Number(invoices.total),
    projected,
  };
}

// ------------------------------------------------------------------ patrimônio

async function snapshotNetWorth(userId = null) {
  const filter = userFilter(userId, 'id');
  const [users] = await db.query(`SELECT id FROM users WHERE deleted_at IS NULL${filter.sql}`, filter.params);
  const today = dates.toIsoDate(new Date());

  for (const { id: uid } of users) {
    const totals = await netWorthTotals(uid);
    await db.query(
      `INSERT INTO net_worth_snapshots
         (user_id, snapshot_date, accounts_total, investments_total, assets_total, debts_total, cards_total, net_worth)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         accounts_total = VALUES(accounts_total), investments_total = VALUES(investments_total),
         assets_total = VALUES(assets_total), debts_total = VALUES(debts_total),
         cards_total = VALUES(cards_total), net_worth = VALUES(net_worth)`,
      [uid, today, totals.accounts, totals.investments, totals.assets, totals.debts, totals.cards, totals.net_worth]
    );
  }

  return { users: users.length };
}

async function netWorthTotals(userId) {
  const [[accounts]] = await db.query(
    'SELECT COALESCE(SUM(current_balance), 0) total FROM accounts WHERE user_id = ? AND active = TRUE',
    [userId]
  );
  const [[investments]] = await db.query(
    'SELECT COALESCE(SUM(current_amount), 0) total FROM investments WHERE user_id = ? AND active = TRUE',
    [userId]
  );
  const [[assets]] = await db.query(
    'SELECT COALESCE(SUM(value), 0) total FROM assets WHERE user_id = ? AND active = TRUE',
    [userId]
  );
  const [[debts]] = await db.query(
    `SELECT COALESCE(SUM(GREATEST(original_amount - paid_amount, 0)), 0) total
     FROM debts WHERE user_id = ? AND status = 'active'`,
    [userId]
  );
  const [[cards]] = await db.query(
    `SELECT COALESCE(SUM(GREATEST(total_amount - paid_amount, 0)), 0) total
     FROM card_invoices WHERE user_id = ? AND paid_amount < total_amount`,
    [userId]
  );

  const assetsTotal = Number(accounts.total) + Number(investments.total) + Number(assets.total);
  const liabilitiesTotal = Number(debts.total) + Number(cards.total);

  return {
    accounts: Number(accounts.total),
    investments: Number(investments.total),
    assets: Number(assets.total),
    debts: Number(debts.total),
    cards: Number(cards.total),
    assets_total: assetsTotal,
    liabilities_total: liabilitiesTotal,
    net_worth: assetsTotal - liabilitiesTotal,
  };
}

// ------------------------------------------------------------------ automações

async function runDueAutomations() {
  const [automations] = await db.query(
    'SELECT * FROM automations WHERE active = TRUE AND (next_run_at IS NULL OR next_run_at <= NOW())'
  );

  let executed = 0;

  for (const automation of automations) {
    let status = 'success';
    let message = null;
    let affected = 0;

    try {
      const result = await executeAutomation(automation);
      affected = result.affected || 0;
      message = result.message || null;
      if (result.skipped) status = 'skipped';
    } catch (err) {
      status = 'failed';
      message = err.message.slice(0, 255);
    }

    await db.query(
      'INSERT INTO automation_runs (automation_id, status, message, affected_rows) VALUES (?, ?, ?, ?)',
      [automation.id, status, message, affected]
    );
    await db.query(
      'UPDATE automations SET last_run_at = NOW(), next_run_at = ? WHERE id = ?',
      [nextRunFor(automation), automation.id]
    );
    executed++;
  }

  return { executed };
}

async function executeAutomation(automation) {
  const config = automation.config ? (typeof automation.config === 'string' ? JSON.parse(automation.config) : automation.config) : {};

  switch (automation.type) {
    case 'recurring_generate': {
      const result = await runDueRecurring(automation.user_id);
      return { affected: result.generated };
    }
    case 'goal_contribution': {
      if (!config.goal_id || !config.amount) return { skipped: true, message: 'Configuração incompleta.' };
      await withTransaction(async conn => {
        await conn.query(
          'INSERT INTO goal_contributions (goal_id, user_id, amount, date, notes) VALUES (?, ?, ?, CURDATE(), ?)',
          [config.goal_id, automation.user_id, config.amount, 'Aporte automático']
        );
        await conn.query('UPDATE goals SET current_amount = current_amount + ? WHERE id = ? AND user_id = ?',
          [config.amount, config.goal_id, automation.user_id]);
      });
      return { affected: 1 };
    }
    case 'invoice_close': {
      const result = await closeDueInvoices();
      return { affected: result.closed };
    }
    case 'notification_scan': {
      const result = await scanNotifications(automation.user_id);
      return { affected: Object.values(result).reduce((a, b) => a + b, 0) };
    }
    case 'net_worth_snapshot': {
      await snapshotNetWorth(automation.user_id);
      return { affected: 1 };
    }
    case 'report':
    case 'backup':
      return { skipped: true, message: 'Execução manual via /import-export.' };
    default:
      return { skipped: true, message: `Tipo não suportado: ${automation.type}` };
  }
}

function nextRunFor(automation) {
  const now = new Date();
  if (automation.frequency === 'daily') return dates.addDays(now, 1);
  if (automation.frequency === 'weekly') return dates.addDays(now, 7);
  const next = dates.addMonths(now, 1);
  if (automation.day_of_month) {
    next.setDate(dates.clampDay(next.getFullYear(), next.getMonth(), automation.day_of_month));
  }
  return next;
}

module.exports = {
  runDueRecurring,
  closeDueInvoices,
  markDueInstallments,
  scanNotifications,
  detectSubscriptions,
  generateInsights,
  forecastMonthEnd,
  snapshotNetWorth,
  netWorthTotals,
  runDueAutomations,
  insight,
  merchantKey,
};
