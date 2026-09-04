const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

router.use(authenticate);

function escapeCsv(value) {
  const str = String(value ?? '');
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return '"' + str.replace(/"/g, '""') + '"';
  }
  return str;
}

router.get('/export', async (req, res) => {
  const { month } = req.query;
  let query = 'SELECT t.id, t.type, t.amount, t.date, t.description, a.name as account, c.name as category FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id LEFT JOIN categories c ON t.category_id = c.id WHERE t.user_id = ?';
  const params = [req.userId];
  if (month) {
    query += ' AND DATE_FORMAT(t.date, "%Y-%m") = ?';
    params.push(month);
  }
  query += ' ORDER BY t.date DESC';

  try {
    const [rows] = await db.query(query, params);
    const header = ['id', 'type', 'amount', 'date', 'description', 'account', 'category'];
    const lines = [header.join(','), ...rows.map(r => [
      r.id,
      r.type,
      r.amount,
      r.date,
      escapeCsv(r.description),
      escapeCsv(r.account),
      escapeCsv(r.category),
    ].join(','))];

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="transacoes.csv"');
    res.send(lines.join('\n'));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/import', async (req, res) => {
  const { transactions } = req.body;
  if (!Array.isArray(transactions) || transactions.length === 0) {
    return res.status(400).json({ error: 'Envie um array de transações.' });
  }

  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    for (const t of transactions) {
      await connection.query(
        'INSERT INTO transactions (user_id, account_id, category_id, type, amount, date, description) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [req.userId, t.account_id, t.category_id, t.type, t.amount, t.date, t.description]
      );
    }
    await connection.commit();
    res.json({ message: `${transactions.length} transações importadas.` });
  } catch (err) {
    await connection.rollback();
    res.status(500).json({ error: err.message });
  } finally {
    connection.release();
  }
});

module.exports = router;
