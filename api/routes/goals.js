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
    await db.query('DELETE FROM goals WHERE id = ? AND user_id = ?', [id, req.userId]);
    res.json({ message: 'Meta removida.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
