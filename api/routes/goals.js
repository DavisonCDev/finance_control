const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

router.use(authenticate);

router.get('/', async (req, res) => {
  try {
    const [rows] = await db.query('SELECT * FROM goals WHERE user_id = ? ORDER BY deadline, name', [req.userId]);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const { name, target_amount, deadline } = req.body;
  if (!name || !target_amount) return res.status(400).json({ error: 'Nome e valor alvo são obrigatórios.' });

  try {
    const [result] = await db.query(
      'INSERT INTO goals (user_id, name, target_amount, deadline) VALUES (?, ?, ?, ?)',
      [req.userId, name, target_amount, deadline]
    );
    const [rows] = await db.query('SELECT * FROM goals WHERE id = ?', [result.insertId]);
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { id } = req.params;
  const { current_amount } = req.body;
  try {
    await db.query('UPDATE goals SET current_amount = current_amount + ? WHERE id = ? AND user_id = ?', [current_amount, id, req.userId]);
    const [rows] = await db.query('SELECT * FROM goals WHERE id = ?', [id]);
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await db.query('SELECT * FROM goals WHERE id = ? AND user_id = ?', [id, req.userId]);
    if (rows.length === 0) return res.status(404).json({ error: 'Meta não encontrada.' });

    const goal = rows[0];
    const current = Number(goal.current_amount || 0);

    if (current > 0) {
      const { account_id } = req.body || {};
      if (!account_id) {
        return res.status(400).json({ error: 'Meta possui saldo. Informe a conta para transferir o aporte antes de excluir.', current_amount: current });
      }
      const [accounts] = await db.query('SELECT id FROM accounts WHERE id = ? AND user_id = ?', [account_id, req.userId]);
      if (accounts.length === 0) return res.status(404).json({ error: 'Conta não encontrada.' });

      await db.query(
        `INSERT INTO transactions
         (user_id, account_id, type, amount, date, description, status, source)
         VALUES (?, ?, 'income', ?, CURDATE(), ?, 'cleared', 'manual')`,
        [req.userId, account_id, current, `Resgate meta: ${goal.name}`]
      );
      await db.query('UPDATE accounts SET current_balance = current_balance + ? WHERE id = ?', [current, account_id]);
    }

    await db.query('DELETE FROM goals WHERE id = ? AND user_id = ?', [id, req.userId]);
    res.json({ message: 'Meta removida. Aporte resgatado para a conta informada.', transferred: current });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Aportes
router.get('/:id/contributions', async (req, res) => {
  try {
    const [rows] = await db.query(
      'SELECT * FROM goal_contributions WHERE goal_id = ? AND user_id = ? ORDER BY date DESC, id DESC',
      [req.params.id, req.userId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/contributions', async (req, res) => {
  const { amount, date, notes } = req.body;
  const goalId = req.params.id;
  if (!amount || Number(amount) <= 0) return res.status(400).json({ error: 'Informe um valor maior que zero.' });

  try {
    const [goals] = await db.query('SELECT id FROM goals WHERE id = ? AND user_id = ?', [goalId, req.userId]);
    if (goals.length === 0) return res.status(404).json({ error: 'Meta não encontrada.' });

    const contributionDate = date || new Date().toISOString().split('T')[0];
    const [result] = await db.query(
      'INSERT INTO goal_contributions (goal_id, user_id, amount, date, notes) VALUES (?, ?, ?, ?, ?)',
      [goalId, req.userId, amount, contributionDate, notes || null]
    );
    await db.query(
      'UPDATE goals SET current_amount = current_amount + ? WHERE id = ? AND user_id = ?',
      [amount, goalId, req.userId]
    );

    const [contributions] = await db.query('SELECT * FROM goal_contributions WHERE id = ?', [result.insertId]);
    const [updated] = await db.query('SELECT * FROM goals WHERE id = ?', [goalId]);
    res.status(201).json({ contribution: contributions[0], goal: updated[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
