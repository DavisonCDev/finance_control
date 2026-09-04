const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

router.use(authenticate);

router.get('/', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT f.*, fm.role FROM families f
       JOIN family_members fm ON f.id = fm.family_id
       WHERE fm.user_id = ?`,
      [req.userId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/', async (req, res) => {
  const { name } = req.body;
  if (!name) return res.status(400).json({ error: 'Nome da família é obrigatório.' });

  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    const [result] = await connection.query('INSERT INTO families (name, owner_id) VALUES (?, ?)', [name, req.userId]);
    await connection.query('INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, ?)', [result.insertId, req.userId, 'admin']);
    await connection.commit();

    const [rows] = await db.query('SELECT * FROM families WHERE id = ?', [result.insertId]);
    res.status(201).json(rows[0]);
  } catch (err) {
    await connection.rollback();
    res.status(500).json({ error: err.message });
  } finally {
    connection.release();
  }
});

router.post('/:id/members', async (req, res) => {
  const { id } = req.params;
  const { email, role } = req.body;

  try {
    const [users] = await db.query('SELECT id FROM users WHERE email = ?', [email]);
    if (users.length === 0) return res.status(404).json({ error: 'Usuário não encontrado.' });

    const [rows] = await db.query(
      'INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, ?)',
      [id, users[0].id, role || 'member']
    );
    res.status(201).json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
