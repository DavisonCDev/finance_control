// Educação financeira: artigos curtos por tema (spec §44).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');

const router = express.Router();
router.use(authenticate);

const CATEGORIES = [
  'budget', 'debt', 'emergency', 'investments',
  'credit_card', 'financing', 'interest', 'planning',
];

// GET / — lista resumida (sem o corpo do texto, que pode ser longo).
router.get('/', asyncHandler(async (req, res) => {
  const params = [];
  let sql = `SELECT id, slug, category, title, summary, reading_minutes, sort_order
             FROM education_contents`;

  if (req.query.category) {
    if (!CATEGORIES.includes(req.query.category)) {
      throw Object.assign(new Error('Categoria inválida.'), { status: 400 });
    }
    sql += ' WHERE category = ?';
    params.push(req.query.category);
  }

  sql += ' ORDER BY category, sort_order, title';

  const [rows] = await db.query(sql, params);
  res.json(rows);
}));

// GET /categories — precede /:slug para não ser capturado como slug.
router.get('/categories', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    `SELECT category, COUNT(*) AS total, MIN(sort_order) AS sort_order
     FROM education_contents
     GROUP BY category
     ORDER BY sort_order, category`
  );
  res.json(rows.map(row => ({ category: row.category, total: Number(row.total) })));
}));

router.get('/:slug', asyncHandler(async (req, res) => {
  const [rows] = await db.query('SELECT * FROM education_contents WHERE slug = ?', [req.params.slug]);
  if (rows.length === 0) {
    throw Object.assign(new Error('Conteúdo educativo não encontrado.'), { status: 404 });
  }
  res.json(rows[0]);
}));

module.exports = router;
