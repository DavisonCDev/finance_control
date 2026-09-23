const db = require('./db');
(async () => {
  const userId = Number(process.argv[2] || 2);
  const [tx] = await db.query(
    `SELECT DATE_FORMAT(COALESCE(accrual_date, date), '%Y-%m') AS month,
            category_id, type, is_paid, card_id, recurring_id, COUNT(*) AS n, SUM(amount) AS total
     FROM transactions WHERE user_id = ? AND deleted_at IS NULL
     GROUP BY month, category_id, type, is_paid, card_id, recurring_id ORDER BY month`, [userId]);
  console.log('=== TRANSACOES ===');
  tx.forEach(r => console.log(r.month, 'cat', r.category_id, r.type, 'paid:' + r.is_paid, 'card:' + r.card_id, 'rec:' + r.recurring_id, 'n:' + r.n, 'total:' + r.total));

  const [b] = await db.query('SELECT budget_month, category_id, amount FROM budgets WHERE user_id = ? ORDER BY budget_month, category_id', [userId]);
  console.log('=== BUDGETS ===');
  b.forEach(r => console.log(r.budget_month, 'cat', r.category_id, 'amount:' + r.amount));

  const [rec] = await db.query('SELECT id, category_id, type, amount, start_date, end_date, active FROM recurring_transactions WHERE user_id = ?', [userId]);
  console.log('=== RECORRENTES ===');
  rec.forEach(r => console.log('id', r.id, 'cat', r.category_id, r.type, 'amt', r.amount, String(r.start_date).slice(0, 10), '->', r.end_date ? String(r.end_date).slice(0, 10) : 'null', 'active:' + r.active));

  // Auditoria: previsto esperado = soma das despesas fora do cartao e fora de recorrencia,
  // mais a previsao das recorrencias ativas (valor por mes coberto).
  const [expected] = await db.query(
    `SELECT DATE_FORMAT(COALESCE(accrual_date, date), '%Y-%m') AS month, category_id, SUM(amount) AS total
     FROM transactions WHERE user_id = ? AND deleted_at IS NULL AND type = 'expense'
       AND category_id IS NOT NULL AND card_id IS NULL AND recurring_id IS NULL
     GROUP BY month, category_id`, [userId]);
  const expMap = {};
  expected.forEach(r => { expMap[r.month + '|' + r.category_id] = Number(r.total); });
  const budMap = {};
  b.forEach(r => { budMap[r.budget_month + '|' + r.category_id] = Number(r.amount); });
  console.log('=== DIVERGENCIAS (budget != soma despesas) ===');
  const keys = new Set([...Object.keys(expMap), ...Object.keys(budMap)]);
  let diff = 0;
  for (const k of [...keys].sort()) {
    const e = expMap[k] || 0, v = budMap[k] || 0;
    if (Math.abs(e - v) > 0.005) { diff++; console.log(k, '-> esperado:', e, 'budget:', v); }
  }
  console.log(diff === 0 ? 'OK: budgets batem com a soma das despesas.' : diff + ' divergencia(s).');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
