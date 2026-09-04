const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

router.use(authenticate);

router.get('/', async (req, res) => {
  const { month } = req.query;
  const targetMonth = month || new Date().toISOString().slice(0, 7);

  try {
    const [events] = await db.query(
      `SELECT * FROM financial_events
       WHERE user_id = ? AND DATE_FORMAT(event_date, '%Y-%m') = ?
       ORDER BY event_date`,
      [req.userId, targetMonth]
    );
    res.json(events);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const { title, type, event_date, amount, description } = req.body;
  if (!title || !event_date) return res.status(400).json({ error: 'Título e data são obrigatórios.' });

  try {
    const [result] = await db.query(
      'INSERT INTO financial_events (user_id, title, type, event_date, amount, description) VALUES (?, ?, ?, ?, ?, ?)',
      [req.userId, title, type || 'other', event_date, amount || 0, description]
    );
    const [rows] = await db.query('SELECT * FROM financial_events WHERE id = ?', [result.insertId]);
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.put('/:id', async (req, res) => {
  const { id } = req.params;
  const { paid } = req.body;

  try {
    await db.query('UPDATE financial_events SET paid = ? WHERE id = ? AND user_id = ?', [paid, id, req.userId]);
    const [rows] = await db.query('SELECT * FROM financial_events WHERE id = ?', [id]);
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
