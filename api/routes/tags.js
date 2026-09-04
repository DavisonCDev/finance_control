// Etiquetas livres para cruzar categorias (spec §24).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');
const ledger = require('../lib/ledger');

const router = express.Router();
router.use(authenticate);

function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 });
}

// O UNIQUE (user_id, name) protege o banco; aqui traduzimos para 409.
function duplicateGuard(err) {
  if (err && err.code === 'ER_DUP_ENTRY') {
    return Object.assign(new Error('Você já tem uma tag com esse nome.'), { status: 409 });
  }
  return err;
}

async function loadTag(userId, id) {
  const [rows] = await db.query('SELECT * FROM tags WHERE id = ? AND user_id = ?', [id, userId]);
  if (rows.length === 0) throw Object.assign(new Error('Tag não encontrada.'), { status: 404 });
  return rows[0];
}

// GET / — tags do usuário com número de lançamentos vinculados.
router.get('/', asyncHandler(async (req, res) => {
  const params = [req.userId];
  let sql = `SELECT tg.*,
                    (SELECT COUNT(*) FROM transaction_tags tt
                      JOIN transactions t ON t.id = tt.transaction_id
                      WHERE tt.tag_id = tg.id AND t.deleted_at IS NULL) AS usage_count
             FROM tags tg
             WHERE tg.user_id = ?`;

  if (req.query.q) {
    sql += ' AND tg.name LIKE ?';
    params.push(`%${req.query.q}%`);
  }

  sql += ' ORDER BY tg.name ASC';

  const [rows] = await db.query(sql, params);
  res.json(rows.map(r => ({ ...r, usage_count: Number(r.usage_count || 0) })));
}));

// GET /:id/transactions — lançamentos marcados com a tag.
router.get('/:id/transactions', asyncHandler(async (req, res) => {
  const tag = await loadTag(req.userId, req.params.id);
  const limit = Math.min(Number(req.query.limit) || 200, 1000);
  const offset = Number(req.query.offset) || 0;

  const [rows] = await db.query(
    `${ledger.TRANSACTION_SELECT}
     JOIN transaction_tags tt ON tt.transaction_id = t.id AND tt.tag_id = ?
     WHERE t.deleted_at IS NULL AND t.user_id = ?
     ORDER BY t.date DESC, t.id DESC
     LIMIT ? OFFSET ?`,
    [tag.id, req.userId, limit, offset]
  );

  const [totals] = await db.query(
    `SELECT COUNT(*) AS total FROM transaction_tags tt
     JOIN transactions t ON t.id = tt.transaction_id
     WHERE tt.tag_id = ? AND t.user_id = ? AND t.deleted_at IS NULL`,
    [tag.id, req.userId]
  );

  res.json({
    tag,
    total: Number(totals[0]?.total || 0),
    transactions: rows.map(r => ({ ...r, tag_names: r.tag_names ? r.tag_names.split(',') : [] })),
  });
}));

// GET /:id — detalhe.
router.get('/:id', asyncHandler(async (req, res) => {
  const tag = await loadTag(req.userId, req.params.id);
  const [counts] = await db.query(
    `SELECT COUNT(*) AS total FROM transaction_tags tt
     JOIN transactions t ON t.id = tt.transaction_id
     WHERE tt.tag_id = ? AND t.deleted_at IS NULL`,
    [tag.id]
  );
  res.json({ ...tag, usage_count: Number(counts[0]?.total || 0) });
}));

// POST / — cria tag.
router.post('/', asyncHandler(async (req, res) => {
  const { name, color } = req.body;
  if (!name || !String(name).trim()) throw badRequest('Nome da tag é obrigatório.');

  let insertId;
  try {
    const [result] = await db.query(
      'INSERT INTO tags (user_id, name, color) VALUES (?, ?, ?)',
      [req.userId, String(name).trim().slice(0, 40), color || '#607D8B']
    );
    insertId = result.insertId;
  } catch (err) {
    throw duplicateGuard(err);
  }

  const [rows] = await db.query('SELECT * FROM tags WHERE id = ?', [insertId]);
  await audit(req.userId, 'tag', insertId, 'create', rows[0]);
  res.status(201).json(rows[0]);
}));

// PUT /:id — renomeia ou troca a cor.
router.put('/:id', asyncHandler(async (req, res) => {
  const before = await loadTag(req.userId, req.params.id);
  const { name, color } = req.body;

  try {
    await db.query(
      'UPDATE tags SET name = ?, color = ? WHERE id = ? AND user_id = ?',
      [
        name === undefined ? before.name : String(name).trim().slice(0, 40),
        color === undefined ? before.color : color,
        before.id, req.userId,
      ]
    );
  } catch (err) {
    throw duplicateGuard(err);
  }

  const [rows] = await db.query('SELECT * FROM tags WHERE id = ?', [before.id]);
  await audit(req.userId, 'tag', before.id, 'update', { before, after: rows[0] });
  res.json(rows[0]);
}));

// DELETE /:id — remove a tag; os vínculos caem por CASCADE.
router.delete('/:id', asyncHandler(async (req, res) => {
  const tag = await loadTag(req.userId, req.params.id);
  const [counts] = await db.query('SELECT COUNT(*) AS total FROM transaction_tags WHERE tag_id = ?', [tag.id]);

  await db.query('DELETE FROM tags WHERE id = ? AND user_id = ?', [tag.id, req.userId]);
  await audit(req.userId, 'tag', tag.id, 'delete', tag);
  res.json({ message: 'Tag excluída.', unlinked_transactions: Number(counts[0]?.total || 0) });
}));

module.exports = router;
