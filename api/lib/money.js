// Conversão cambial e formatação (spec §26).
const db = require('../db');

async function latestRate(base, quote, date = null) {
  if (base === quote) return 1;

  const [rows] = await db.query(
    `SELECT rate FROM exchange_rates
     WHERE base_code = ? AND quote_code = ? ${date ? 'AND rate_date <= ?' : ''}
     ORDER BY rate_date DESC LIMIT 1`,
    date ? [base, quote, date] : [base, quote]
  );
  if (rows.length > 0) return Number(rows[0].rate);

  // Tenta o par invertido antes de desistir.
  const [inverse] = await db.query(
    `SELECT rate FROM exchange_rates
     WHERE base_code = ? AND quote_code = ? ${date ? 'AND rate_date <= ?' : ''}
     ORDER BY rate_date DESC LIMIT 1`,
    date ? [quote, base, date] : [quote, base]
  );
  if (inverse.length > 0 && Number(inverse[0].rate) !== 0) return 1 / Number(inverse[0].rate);

  return null;
}

async function convert(amount, from, to, date = null) {
  const rate = await latestRate(from, to, date);
  if (rate === null) {
    const error = new Error(`Sem cotação cadastrada para ${from}→${to}.`);
    error.status = 400;
    throw error;
  }
  return { amount: Number((Number(amount) * rate).toFixed(2)), rate };
}

async function upsertRate(base, quote, rate, rateDate) {
  await db.query(
    `INSERT INTO exchange_rates (base_code, quote_code, rate, rate_date) VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE rate = VALUES(rate)`,
    [base, quote, rate, rateDate]
  );
}

module.exports = { latestRate, convert, upsertRate };
