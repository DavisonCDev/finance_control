// Categorias e subcategorias, próprias e padrão do sistema (spec §8).
const express = require('express');
const db = require('../db');
const { withTransaction } = require('../db');
const authenticate = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const { audit } = require('../lib/audit');

const router = express.Router();
router.use(authenticate);

const CATEGORY_TYPES = ['income', 'expense'];

function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 });
}

function parseBool(value) {
  if (value === undefined || value === null || value === '') return undefined;
  return value === true || value === 'true' || value === 1 || value === '1';
}

async function loadCategory(userId, id) {
  const [rows] = await db.query(
    'SELECT * FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL)',
    [id, userId]
  );
  if (rows.length === 0) throw Object.assign(new Error('Categoria não encontrada.'), { status: 404 });
  return rows[0];
}

// Categorias padrão são compartilhadas por todos: ninguém pode alterá-las.
function assertEditable(category) {
  if (category.user_id === null || category.is_system) {
    throw Object.assign(new Error('Categorias padrão não podem ser editadas.'), { status: 403 });
  }
}

/**
 * Valida o pai de uma subcategoria: precisa existir, ser do mesmo tipo e ser
 * uma raiz — o modelo permite no máximo 2 níveis.
 */
async function assertValidParent(userId, parentId, type, selfId = null) {
  const parent = await loadCategory(userId, parentId);
  if (selfId && Number(parent.id) === Number(selfId)) {
    throw badRequest('Uma categoria não pode ser a própria categoria-pai.');
  }
  if (parent.type !== type) throw badRequest('A subcategoria deve ter o mesmo tipo da categoria-pai.');
  if (parent.parent_id) throw badRequest('Só é permitido um nível de subcategoria.');
  return parent;
}

// GET / — árvore (padrão) ou lista plana com ?flat=true.
router.get('/', asyncHandler(async (req, res) => {
  const { type, parent_id, flat } = req.query;

  const params = [req.userId, req.userId];
  let sql = `SELECT c.*,
                    (SELECT COUNT(*) FROM transactions t
                      WHERE t.category_id = c.id AND t.user_id = ? AND t.deleted_at IS NULL) AS usage_count
             FROM categories c
             WHERE (c.user_id = ? OR c.user_id IS NULL)`;

  if (type) {
    if (!CATEGORY_TYPES.includes(type)) throw badRequest("Tipo inválido. Use 'income' ou 'expense'.");
    sql += ' AND c.type = ?';
    params.push(type);
  }
  if (parent_id !== undefined && parent_id !== '') {
    sql += ' AND c.parent_id = ?';
    params.push(parent_id);
  }
  const active = parseBool(req.query.active);
  if (active !== undefined) {
    sql += ' AND c.active = ?';
    params.push(active ? 1 : 0);
  }

  sql += ' ORDER BY c.sort_order ASC, c.name ASC';

  const [rows] = await db.query(sql, params);
  const normalized = rows.map(r => ({ ...r, usage_count: Number(r.usage_count || 0) }));

  if (parseBool(flat) || (parent_id !== undefined && parent_id !== '')) {
    return res.json(normalized);
  }

  const roots = normalized.filter(c => !c.parent_id).map(c => ({ ...c, subcategories: [] }));
  const index = new Map(roots.map(c => [Number(c.id), c]));
  const orphans = [];

  for (const category of normalized) {
    if (!category.parent_id) continue;
    const parent = index.get(Number(category.parent_id));
    // Quando o filtro esconde o pai (ex.: pai inativo), a filha vira raiz.
    if (parent) parent.subcategories.push(category);
    else orphans.push({ ...category, subcategories: [] });
  }

  res.json([...roots, ...orphans]);
}));

// POST / — cria categoria ou subcategoria.
router.post('/', asyncHandler(async (req, res) => {
  const { name, type, color, icon, parent_id, sort_order } = req.body;
  if (!name || !String(name).trim()) throw badRequest('Nome da categoria é obrigatório.');
  if (!type || !CATEGORY_TYPES.includes(type)) throw badRequest("Tipo é obrigatório e deve ser 'income' ou 'expense'.");

  if (parent_id) await assertValidParent(req.userId, parent_id, type);

  const [result] = await db.query(
    `INSERT INTO categories (user_id, name, type, color, icon, parent_id, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      req.userId, String(name).trim(), type,
      color || '#607D8B', icon || 'category',
      parent_id || null, Number(sort_order) || 0,
    ]
  );

  const [rows] = await db.query('SELECT * FROM categories WHERE id = ?', [result.insertId]);
  await audit(req.userId, 'category', result.insertId, 'create', rows[0]);
  res.status(201).json(rows[0]);
}));

// PUT /reorder — declarado antes de /:id para não ser capturado pelo parâmetro.
router.put('/reorder', asyncHandler(async (req, res) => {
  const items = Array.isArray(req.body?.items) ? req.body.items : null;
  if (!items || items.length === 0) throw badRequest('Envie a lista de itens com id e sort_order.');

  const updated = await withTransaction(async conn => {
    let count = 0;
    for (const item of items) {
      if (!item || !item.id) continue;
      const [result] = await conn.query(
        'UPDATE categories SET sort_order = ? WHERE id = ? AND user_id = ?',
        [Number(item.sort_order) || 0, item.id, req.userId]
      );
      count += result.affectedRows;
    }
    return count;
  });

  await audit(req.userId, 'category', null, 'update', { reorder: items });
  res.json({ message: 'Ordem atualizada.', updated });
}));

// PUT /:id — só categorias do próprio usuário.
router.put('/:id', asyncHandler(async (req, res) => {
  const before = await loadCategory(req.userId, req.params.id);
  assertEditable(before);

  const { name, color, icon, parent_id, sort_order, active } = req.body;

  let nextParent = parent_id === undefined ? before.parent_id : (parent_id || null);
  if (nextParent && Number(nextParent) !== Number(before.parent_id || 0)) {
    await assertValidParent(req.userId, nextParent, before.type, before.id);
  }
  // Categoria com filhas não pode virar subcategoria (limite de 2 níveis).
  if (nextParent) {
    const [children] = await db.query('SELECT COUNT(*) AS total FROM categories WHERE parent_id = ?', [before.id]);
    if (Number(children[0]?.total || 0) > 0) {
      throw badRequest('Esta categoria possui subcategorias e não pode se tornar uma subcategoria.');
    }
  }

  await db.query(
    `UPDATE categories SET name = ?, color = ?, icon = ?, parent_id = ?, sort_order = ?, active = ?
     WHERE id = ? AND user_id = ?`,
    [
      name === undefined ? before.name : String(name).trim(),
      color === undefined ? before.color : color,
      icon === undefined ? before.icon : icon,
      nextParent,
      sort_order === undefined ? before.sort_order : (Number(sort_order) || 0),
      active === undefined ? before.active : (parseBool(active) ? 1 : 0),
      before.id, req.userId,
    ]
  );

  const [rows] = await db.query('SELECT * FROM categories WHERE id = ?', [before.id]);
  await audit(req.userId, 'category', before.id, 'update', { before, after: rows[0] });
  res.json(rows[0]);
}));

// DELETE /:id — exige reatribuição quando há lançamentos vinculados.
router.delete('/:id', asyncHandler(async (req, res) => {
  const category = await loadCategory(req.userId, req.params.id);
  if (category.user_id === null || category.is_system) {
    throw Object.assign(new Error('Categorias padrão não podem ser excluídas.'), { status: 403 });
  }

  const [children] = await db.query('SELECT id FROM categories WHERE parent_id = ?', [category.id]);
  const childIds = children.map(c => c.id);
  const affectedIds = [category.id, ...childIds];
  const placeholders = affectedIds.map(() => '?').join(', ');

  const [counts] = await db.query(
    `SELECT COUNT(*) AS total FROM transactions WHERE category_id IN (${placeholders}) AND deleted_at IS NULL`,
    affectedIds
  );
  const total = Number(counts[0]?.total || 0);

  const reassignTo = req.query.reassign_to;
  if (total > 0 && !reassignTo) {
    throw Object.assign(
      new Error(`Esta categoria (e suas subcategorias) possui ${total} lançamento(s). Informe ?reassign_to=<categoryId> para reatribuí-los antes de excluir.`),
      { status: 409 }
    );
  }

  if (total > 0) {
    const target = await loadCategory(req.userId, reassignTo);
    if (affectedIds.some(id => Number(id) === Number(target.id))) {
      throw badRequest('A categoria de destino não pode ser a própria categoria excluída nem uma de suas subcategorias.');
    }
    if (target.type !== category.type) throw badRequest('A categoria de destino deve ter o mesmo tipo.');

    await withTransaction(async conn => {
      await conn.query(
        `UPDATE transactions SET category_id = ? WHERE category_id IN (${placeholders}) AND user_id = ?`,
        [target.id, ...affectedIds, req.userId]
      );
      // FK ON DELETE CASCADE remove as subcategorias junto.
      await conn.query('DELETE FROM categories WHERE id = ? AND user_id = ?', [category.id, req.userId]);
    });

    await audit(req.userId, 'category', category.id, 'delete', { reassigned_to: target.id, transactions: total });
    return res.json({
      message: 'Categoria excluída e lançamentos reatribuídos.',
      reassigned_transactions: total,
      reassigned_to: target.id,
      removed_subcategories: childIds.length,
    });
  }

  await db.query('DELETE FROM categories WHERE id = ? AND user_id = ?', [category.id, req.userId]);
  await audit(req.userId, 'category', category.id, 'delete', category);
  res.json({
    message: 'Categoria excluída.',
    reassigned_transactions: 0,
    removed_subcategories: childIds.length,
  });
}));

module.exports = router;
