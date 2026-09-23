const db = require('../db');

async function ensureBudget(userId, categoryId, month, amount, conn = null) {
  if (!categoryId || !month || amount == null) return;
  const parsedAmount = Number(amount);
  if (Number.isNaN(parsedAmount)) return;

  const q = conn || db;
  const [existing] = await q.query(
    'SELECT id, amount FROM budgets WHERE user_id = ? AND category_id = ? AND budget_month = ?',
    [userId, categoryId, month]
  );

  if (existing.length === 0) {
    if (parsedAmount <= 0) return;
    await q.query(
      `INSERT INTO budgets (user_id, category_id, budget_month, amount, alert_threshold)
       VALUES (?, ?, ?, ?, 80)`,
      [userId, categoryId, month, parsedAmount]
    );
  } else {
    const nextAmount = Number(existing[0].amount) + parsedAmount;
    if (nextAmount <= 0) {
      await q.query(
        'DELETE FROM budgets WHERE id = ?',
        [existing[0].id]
      );
    } else {
      await q.query(
        'UPDATE budgets SET amount = ? WHERE id = ?',
        [nextAmount, existing[0].id]
      );
    }
  }
}

async function ensureBudgetForTransaction(userId, tx, conn = null) {
  // Transacoes geradas por recorrencia nao alteram a previsao:
  // a recorrencia ja previu o valor para todos os meses.
  // Compras no cartao tambem nao: quem preve e a fatura.
  // Pagamento de fatura nao cria previsao na categoria: o previsto/gasto de
  // cartao vem direto das faturas (card_invoices), senao contaria em dobro.
  if (tx.recurring_id || tx.card_id || tx.source === 'invoice_payment') return;
  if (tx.type !== 'expense' || !tx.category_id) return;
  const rawDate = tx.accrual_date || tx.date;
  if (!rawDate) return;
  const month = String(rawDate).slice(0, 7);
  if (!/^\d{4}-\d{2}$/.test(month)) return;
  await ensureBudget(userId, tx.category_id, month, Number(tx.amount), conn);
}

async function ensureBudgetsForRecurring(userId, recurring) {
  if (recurring.type !== 'expense' || !recurring.category_id) return;

  const start = new Date(recurring.start_date);
  const end = recurring.end_date
    ? new Date(recurring.end_date)
    : new Date(start.getFullYear() + 5, 11, 31);

  const months = new Set();
  const d = new Date(start);
  while (d <= end) {
    const m = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    months.add(m);
    d.setMonth(d.getMonth() + 1);
  }

  const amount = Number(recurring.amount);
  if (Number.isNaN(amount) || amount <= 0) return;

  for (const month of months) {
    await ensureBudget(userId, recurring.category_id, month, amount);
  }
}

module.exports = {
  ensureBudget,
  ensureBudgetForTransaction,
  ensureBudgetsForRecurring,
};
