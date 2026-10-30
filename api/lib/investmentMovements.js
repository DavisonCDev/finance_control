// Movimentos de investimento ligados a lancamentos: recalcula totais e
// mantem o movimento em sincronia com a transacao que o gerou.
//
// Regra: uma transacao com investment_id so vira movimento quando esta
// paga (aporte/resgate confirmado). Ao desmarcar ou excluir a transacao,
// o movimento some junto — o dinheiro nunca entrou/saiu de fato.
//
// O tipo do movimento vem do prefixo da descricao ("Aporte:", "Resgate:",
// "Dividendo:", "Rendimento:"); sem prefixo usa o tipo da transacao.
const KIND_BY_PREFIX = {
  'aporte:': 'contribution',
  'resgate:': 'withdrawal',
  'dividendo:': 'dividend',
  'rendimento:': 'yield',
};

function round(value, decimals = 2) {
  const factor = 10 ** decimals;
  return Math.round((Number(value) + Number.EPSILON) * factor) / factor;
}

/**
 * Recalcula invested_amount/current_amount reproduzindo os movimentos em ordem.
 * Reprocessar é mais seguro que somar/subtrair incrementalmente: garante que a
 * exclusão de um movimento (inclusive de uma marcação a mercado, que sobrescreve
 * o valor atual) deixe os totais coerentes com o histórico restante.
 */
async function recomputeTotals(conn, investmentId) {
  const [movements] = await conn.query(
    'SELECT kind, amount FROM investment_movements WHERE investment_id = ? ORDER BY date ASC, id ASC',
    [investmentId]
  );

  let invested = 0;
  let current = 0;
  for (const m of movements) {
    const amount = Number(m.amount || 0);
    if (m.kind === 'contribution') { invested += amount; current += amount; }
    else if (m.kind === 'withdrawal') { invested -= amount; current -= amount; }
    else if (m.kind === 'dividend' || m.kind === 'yield') current += amount;
    else if (m.kind === 'fee' || m.kind === 'tax') current -= amount;
    else if (m.kind === 'valuation') current = amount;
  }

  invested = round(Math.max(invested, 0));
  current = round(Math.max(current, 0));

  await conn.query('UPDATE investments SET invested_amount = ?, current_amount = ? WHERE id = ?', [invested, current, investmentId]);
  return { invested_amount: invested, current_amount: current };
}

function kindFor(tx) {
  const desc = String(tx.description || '').trim().toLowerCase();
  for (const prefix in KIND_BY_PREFIX) {
    if (desc.startsWith(prefix)) return KIND_BY_PREFIX[prefix];
  }
  if (tx.type === 'expense') return 'contribution';
  if (tx.type === 'income') return 'withdrawal';
  return null;
}

/**
 * Garante que exista exatamente um movimento para a transacao, espelhando
 * valor e data. Nao faz nada quando a transacao nao esta paga — e remove
 * o movimento caso ela tenha sido desconfirmada.
 */
async function syncForTransaction(conn, userId, transactionId) {
  const [rows] = await conn.query(
    `SELECT id, investment_id, type, amount, date, description, status, is_paid
     FROM transactions WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
    [transactionId, userId]
  );
  const tx = rows[0];
  if (!tx || !tx.investment_id) return;

  const [movements] = await conn.query(
    'SELECT id FROM investment_movements WHERE transaction_id = ?',
    [transactionId]
  );
  const active = tx.is_paid && tx.status !== 'cancelled' && tx.status !== 'scheduled';

  if (!active) {
    if (movements.length > 0) {
      await conn.query('DELETE FROM investment_movements WHERE transaction_id = ?', [transactionId]);
      await recomputeTotals(conn, tx.investment_id);
    }
    return;
  }

  const kind = kindFor(tx);
  if (!kind) return;
  const date = String(tx.date).slice(0, 10);
  if (movements.length > 0) {
    await conn.query(
      'UPDATE investment_movements SET kind = ?, amount = ?, date = ? WHERE transaction_id = ?',
      [kind, tx.amount, date, transactionId]
    );
  } else {
    await conn.query(
      'INSERT INTO investment_movements (investment_id, kind, amount, date, transaction_id) VALUES (?, ?, ?, ?, ?)',
      [tx.investment_id, kind, tx.amount, date, transactionId]
    );
  }
  await recomputeTotals(conn, tx.investment_id);
}

// Chamado quando a transacao e excluida de vez: remove o movimento ligado.
async function removeForTransaction(conn, tx) {
  if (!tx.investment_id) return;
  const [result] = await conn.query(
    'DELETE FROM investment_movements WHERE transaction_id = ?',
    [tx.id]
  );
  if (result.affectedRows > 0) await recomputeTotals(conn, tx.investment_id);
}

module.exports = { recomputeTotals, syncForTransaction, removeForTransaction };
