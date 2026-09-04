// Moedas e cotações (spec §26).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const money = require('../lib/money');
const { audit } = require('../lib/audit');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM currencies ORDER BY code');
  res.json({ currencies: rows });
}));

router.get('/rates', asyncHandler(async (req, res) => {
  const { base, quote, days = 30 } = req.query;
  const limit = Math.min(Number(days) || 30, 365);
  let sql = 'SELECT * FROM exchange_rates WHERE rate_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)';
  const params = [limit];
  if (base) { sql += ' AND base_code = ?'; params.push(base); }
  if (quote) { sql += ' AND quote_code = ?'; params.push(quote); }
  sql += ' ORDER BY rate_date DESC, base_code, quote_code';
  const [rows] = await db.query(sql, params);
  res.json({ rates: rows });
}));

router.post('/rates', asyncHandler(async (req, res) => {
  const { base_code, quote_code, rate, rate_date } = req.body;
  if (!base_code || !quote_code || rate === undefined) throw Object.assign(new Error('base_code, quote_code e rate são obrigatórios.'), { status: 400 });
  const [currencies] = await db.query('SELECT code FROM currencies WHERE code IN (?, ?)', [base_code, quote_code]);
  if (currencies.length < 2) throw Object.assign(new Error('Moeda não cadastrada.'), { status: 400 });
  const date = rate_date || new Date().toISOString().slice(0, 10);
  await money.upsertRate(base_code, quote_code, rate, date);
  await audit(req.userId, 'exchange_rate', `${base_code}-${quote_code}`, 'create');
  res.status(201).json({ message: 'Cotação registrada.' });
}));

router.get('/convert', asyncHandler(async (req, res) => {
  const { amount, from, to, date } = req.query;
  if (!amount || !from || !to) throw Object.assign(new Error('Informe amount, from e to.'), { status: 400 });
  const result = await money.convert(amount, from, to, date || null);
  res.json({ amount: Number(amount), converted: Number(result.amount), rate: Number(result.rate), from, to });
}));

router.post('/rates/sync', asyncHandler(async (req, res) => {
  const [userRows] = await db.query('SELECT currency FROM users WHERE id = ?', [req.userId]);
  const [accountCurrencies] = await db.query('SELECT DISTINCT currency FROM accounts WHERE user_id = ? AND currency IS NOT NULL', [req.userId]);
  const codes = new Set([userRows[0]?.currency || 'BRL', ...accountCurrencies.map(a => a.currency)]);
  res.status(501).json({
    message: 'Sincronização com provedor externo não configurada. Defina EXCHANGE_API_URL e EXCHANGE_API_KEY no .env.',
    used_pairs: [...codes].map(c => `${(userRows[0]?.currency || 'BRL')}-${c}`).filter(p => !p.endsWith('-' + (userRows[0]?.currency || 'BRL')))
  });
}));

module.exports = router;
