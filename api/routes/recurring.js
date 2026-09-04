const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

function addDate(date, frequency) {
  const d = new Date(date);
  switch (frequency) {
    case 'daily': d.setDate(d.getDate() + 1); break;
    case 'weekly': d.setDate(d.getDate() + 7); break;
    case 'monthly': d.setMonth(d.getMonth() + 1); break;
    case 'yearly': d.setFullYear(d.getFullYear() + 1); break;
  }
  return d.toISOString().slice(0, 10);
}

router.use(authenticate);

router.get('/', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT r.*, c.name as category_name, a.name as account_name
       FROM recurring_transactions r
       LEFT JOIN categories c ON r.category_id = c.id
       LEFT JOIN accounts a ON r.account_id = a.id
       WHERE r.user_id = ? AND r.active = TRUE
       ORDER BY r.next_date`,
      [req.userId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const { account_id, category_id, type, amount, description, frequency, start_date, end_date } = req.body;
  if (!type || !amount || !start_date || !frequency) {
    return res.status(400).json({ error: 'Tipo, valor, data início e frequência são obrigatórios.' });
  }

  try {
    const [result] = await db.query(
      'INSERT INTO recurring_transactions (user_id, account_id, category_id, type, amount, description, frequency, start_date, end_date, next_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [req.userId, account_id, category_id, type, amount, description, frequency, start_date, end_date, start_date]
    );
    const [rows] = await db.query('SELECT * FROM recurring_transactions WHERE id = ?', [result.insertId]);
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/generate', async (req, res) => {
  const { id } = req.params;
  const connection = await db.getConnection();

  try {
    await connection.beginTransaction();

    const [rows] = await connection.query(
      'SELECT * FROM recurring_transactions WHERE id = ? AND user_id = ? AND active = TRUE',
      [id, req.userId]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'Recorrência não encontrada.' });

    const r = rows[0];
    if (r.end_date && new Date(r.next_date) > new Date(r.end_date)) {
      await connection.query('UPDATE recurring_transactions SET active = FALSE WHERE id = ?', [id]);
      await connection.commit();
      return res.json({ message: 'Recorrência finalizada.' });
    }

    await connection.query(
      'INSERT INTO transactions (user_id, account_id, category_id, type, amount, date, description) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [r.user_id, r.account_id, r.category_id, r.type, r.amount, r.next_date, r.description]
    );

    if (r.account_id && r.type === 'income') {
      await connection.query('UPDATE accounts SET current_balance = current_balance + ? WHERE id = ?', [r.amount, r.account_id]);
    } else if (r.account_id && r.type === 'expense') {
      await connection.query('UPDATE accounts SET current_balance = current_balance - ? WHERE id = ?', [r.amount, r.account_id]);
    }

    const next = addDate(r.next_date, r.frequency);
    if (r.end_date && new Date(next) > new Date(r.end_date)) {
      await connection.query('UPDATE recurring_transactions SET active = FALSE WHERE id = ?', [id]);
    } else {
      await connection.query('UPDATE recurring_transactions SET next_date = ? WHERE id = ?', [next, id]);
    }

    await connection.commit();
    res.json({ message: 'Transação gerada com sucesso.' });
  } catch (err) {
    await connection.rollback();
    res.status(500).json({ error: err.message });
  } finally {
    connection.release();
  }
});

module.exports = router;
