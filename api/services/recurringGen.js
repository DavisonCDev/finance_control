const dates = require('../lib/dates');
const ledger = require('../lib/ledger');

// Gera todas as ocorrencias da recorrencia ate `upTo` (inclusive), criando
// transacoes reais. Ocorrencias com data futura ficam is_paid=false — nao
// mexem no saldo nem no "gasto" ate o usuario confirmar o pagamento.
async function generateUpTo(conn, userId, recurring, upTo) {
  const today = dates.toIsoDate(new Date());
  let next = String(recurring.next_date || recurring.start_date).slice(0, 10);
  const limit = String(upTo).slice(0, 10);
  let generated = 0;

  while (next <= limit && generated < 600) {
    await ledger.createTransaction(conn, userId, {
      account_id: recurring.account_id,
      category_id: recurring.category_id,
      type: recurring.type,
      amount: recurring.amount,
      date: next,
      accrual_date: next,
      payment_date: next,
      is_paid: next <= today,
      description: recurring.description,
      recurring_id: recurring.id,
      source: 'recurring',
    });
    generated++;
    next = dates.nextOccurrence(next, recurring.frequency);
  }

  const finished =
    recurring.end_date && next > String(recurring.end_date).slice(0, 10);
  if (finished) {
    await conn.query(
      'UPDATE recurring_transactions SET active = FALSE, next_date = ? WHERE id = ?',
      [next, recurring.id]
    );
  } else {
    await conn.query(
      'UPDATE recurring_transactions SET next_date = ? WHERE id = ?',
      [next, recurring.id]
    );
  }
  return generated;
}

// Gera o que ja venceu (next_date <= hoje) para todas as recorrencias ativas
// do usuario. Chamado na listagem de transacoes como "catch-up".
async function generateDue(conn, userId) {
  const today = dates.toIsoDate(new Date());
  const [rows] = await conn.query(
    'SELECT * FROM recurring_transactions WHERE user_id = ? AND active = TRUE AND next_date <= ?',
    [userId, today]
  );
  for (const r of rows) {
    await generateUpTo(conn, userId, r, today);
  }
  return rows.length;
}

module.exports = { generateUpTo, generateDue };
