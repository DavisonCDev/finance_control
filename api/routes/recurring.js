const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { ensureBudget, ensureBudgetsForRecurring } = require('../services/autoBudget');
const { generateUpTo } = require('../services/recurringGen');
const { withTransaction } = require('../db');
const ledger = require('../lib/ledger');
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
      `SELECT r.*, CASE WHEN p.name IS NULL THEN c.name ELSE CONCAT(p.name, ' › ', c.name) END as category_name, a.name as account_name
       FROM recurring_transactions r
       LEFT JOIN categories c ON r.category_id = c.id
       LEFT JOIN categories p ON p.id = c.parent_id
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

    try {
      await ensureBudgetsForRecurring(req.userId, rows[0]);
    } catch (budgetErr) {
      // Nao impede a criacao da recorrencia se o orcamento falhar.
    }

    // Gera as ocorrencias de uma vez: com data final, todas ate end_date;
    // sem data final, apenas as que ja venceram. Futuras ficam "a pagar".
    try {
      const upTo = end_date || new Date().toISOString().slice(0, 10);
      await withTransaction(conn => generateUpTo(conn, req.userId, rows[0], upTo));
    } catch (genErr) {
      // Nao impede a criacao da recorrencia se a geracao falhar.
    }

    const [created] = await db.query('SELECT * FROM recurring_transactions WHERE id = ?', [result.insertId]);
    res.status(201).json(created[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

function monthsBetween(startDate, endDate, defaultYears = 5) {
  const start = new Date(startDate);
  const end = endDate
    ? new Date(endDate)
    : new Date(start.getFullYear() + defaultYears, 11, 31);

  const months = new Set();
  const d = new Date(start);
  while (d <= end) {
    const m = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    months.add(m);
    d.setMonth(d.getMonth() + 1);
  }
  return months;
}

router.put('/:id', async (req, res) => {
  const { id } = req.params;
  const { account_id, category_id, type, amount, description, frequency, start_date, end_date } = req.body;

  try {
    const [rows] = await db.query(
      'SELECT * FROM recurring_transactions WHERE id = ? AND user_id = ? AND active = TRUE',
      [id, req.userId]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'Recorrência não encontrada.' });

    const before = rows[0];
    const oldMonths = monthsBetween(before.start_date, before.end_date);
    const newMonths = monthsBetween(start_date, end_date);

    const [result] = await db.query(
      `UPDATE recurring_transactions
       SET account_id = ?, category_id = ?, type = ?, amount = ?, description = ?,
           frequency = ?, start_date = ?, end_date = ?, next_date = ?
       WHERE id = ?`,
      [
        account_id, category_id, type, amount, description,
        frequency, start_date, end_date,
        new Date(start_date) <= new Date(before.start_date) ? start_date : before.next_date,
        id
      ]
    );

    // Ajusta previsões: remove valores antigos e aplica novos.
    try {
      for (const month of oldMonths) {
        await ensureBudget(req.userId, before.category_id, month, -Number(before.amount));
      }
      for (const month of newMonths) {
        await ensureBudget(req.userId, category_id, month, Number(amount));
      }
    } catch (budgetErr) {
      // Nao impede a atualizacao.
    }

    const [updated] = await db.query('SELECT * FROM recurring_transactions WHERE id = ?', [id]);
    res.json(updated[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await db.query(
      'SELECT * FROM recurring_transactions WHERE id = ? AND user_id = ? AND active = TRUE',
      [id, req.userId]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'Recorrência não encontrada.' });

    const r = rows[0];
    const connection = await db.getConnection();
    try {
      await connection.beginTransaction();
      // Remove transacoes ja geradas e reverte efeitos pelo ledger.
      const [txs] = await connection.query(
        'SELECT * FROM transactions WHERE recurring_id = ? AND user_id = ? AND deleted_at IS NULL',
        [id, req.userId]
      );
      for (const t of txs) {
        await ledger.deleteTransaction(connection, req.userId, t.id);
      }
      // Remove a previsao criada pela recorrencia em todos os meses cobertos.
      if (r.type === 'expense' && r.category_id) {
        for (const month of monthsBetween(r.start_date, r.end_date)) {
          await ensureBudget(req.userId, r.category_id, month, -Number(r.amount), connection);
        }
      }
      await connection.query('DELETE FROM recurring_transactions WHERE id = ?', [id]);
      await connection.commit();
      res.json({ message: 'Recorrência e transações geradas removidas.', removed: r });
    } catch (err) {
      await connection.rollback();
      throw err;
    } finally {
      connection.release();
    }
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

    await ledger.createTransaction(connection, req.userId, {
      account_id: r.account_id,
      category_id: r.category_id,
      type: r.type,
      amount: r.amount,
      date: r.next_date,
      accrual_date: r.next_date,
      payment_date: r.next_date,
      is_paid: true,
      description: r.description,
      recurring_id: r.id,
      source: 'recurring',
    });

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
