// Patrimônio líquido e bens (spec §19).
const express = require('express');
const db = require('../db');
const authenticate = require('../middleware/auth');
const { requireFeature } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/errors');
const jobs = require('../lib/jobs');
const scope = require('../lib/scope');
const { audit } = require('../lib/audit');
const dates = require('../lib/dates');

const router = express.Router();
router.use(authenticate);

const TYPES = ['vehicle','property','equipment','valuable','receivable','other'];

router.get('/', asyncHandler(async (req, res) => {
  const totals = await jobs.netWorthTotals(req.userId);
  res.json({
    assets: {
      total: totals.assets_total,
      cash_and_accounts: totals.accounts,
      investments: totals.investments,
      physical_assets: totals.assets,
      breakdown: [
        { label: 'Contas', value: totals.accounts },
        { label: 'Investimentos', value: totals.investments },
        { label: 'Bens', value: totals.assets }
      ]
    },
    liabilities: {
      total: totals.liabilities_total,
      debts: totals.debts,
      cards: totals.cards,
      breakdown: [
        { label: 'Dívidas', value: totals.debts },
        { label: 'Cartões', value: totals.cards }
      ]
    },
    net_worth: totals.net_worth,
    snapshot_date: dates.toIsoDate(new Date())
  });
}));

router.get('/assets', asyncHandler(async (req, res) => {
  const q = req.query;
  const visibility = await scope.visibilityClause(req.userId, 'a');
  const conditions = ['a.deleted_at IS NULL', visibility.sql];
  const params = [...visibility.params];
  if (q.active) { conditions.push('a.active = ?'); params.push(q.active); }
  if (q.type) { conditions.push('a.type = ?'); params.push(q.type); }
  const [rows] = await db.query(
    `SELECT a.* FROM assets a WHERE ${conditions.join(' AND ')} ORDER BY a.value DESC`,
    params
  );
  res.json({ assets: rows.map(r => ({
    ...r,
    depreciated_value: (r.depreciation_rate && r.acquisition_date) ? Math.max(0, Number(r.value) * (1 - (Number(r.depreciation_rate)/100) * ((new Date().getFullYear() - new Date(r.acquisition_date).getFullYear())))) : Number(r.value),
    appreciation: (r.acquisition_value ? Number(r.value) - Number(r.acquisition_value) : null)
  }))});
}));

router.post('/assets', requireFeature('assets'), asyncHandler(async (req, res) => {
  const b = req.body;
  if (!b.name || b.value === undefined) throw Object.assign(new Error('Nome e valor são obrigatórios.'), { status: 400 });
  if (b.type && !TYPES.includes(b.type)) throw Object.assign(new Error('Tipo inválido.'), { status: 400 });
  await scope.assertCanUseFamily(req.userId, b.family_id);
  const [result] = await db.query(
    'INSERT INTO assets (user_id, family_id, name, type, value, acquisition_value, acquisition_date, depreciation_rate, notes, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)',
    [req.userId, b.family_id || null, b.name, b.type || 'other', b.value, b.acquisition_value || null, b.acquisition_date || null, b.depreciation_rate || null, b.notes || null]
  );
  await audit(req.userId, 'asset', result.insertId, 'create');
  res.status(201).json({ id: result.insertId, message: 'Bem cadastrado.' });
}));

router.put('/assets/:id', requireFeature('assets'), asyncHandler(async (req, res) => {
  const id = req.params.id;
  const b = req.body;
  const fields = ['name','type','value','acquisition_value','acquisition_date','depreciation_rate','notes','active'];
  const updates = []; const values = [];
  for (const f of fields) { if (b[f] !== undefined) { updates.push(`${f} = ?`); values.push(b[f] !== '' ? b[f] : null); } }
  if (updates.length === 0) return res.json({});
  values.push(id, req.userId);
  await db.query(`UPDATE assets SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`, values);
  await audit(req.userId, 'asset', id, 'update');
  res.json({ id, message: 'Bem atualizado.' });
}));

router.delete('/assets/:id', requireFeature('assets'), asyncHandler(async (req, res) => {
  const id = req.params.id;
  await db.query('DELETE FROM assets WHERE id = ? AND user_id = ?', [id, req.userId]);
  await audit(req.userId, 'asset', id, 'delete');
  res.json({ id, message: 'Bem removido.' });
}));

router.get('/evolution', asyncHandler(async (req, res) => {
  const months = Math.min(Math.max(Number(req.query.months) || 12, 3), 24);
  const [rows] = await db.query(
    `SELECT * FROM net_worth_snapshots
     WHERE user_id = ? AND snapshot_date >= DATE_SUB(CURDATE(), INTERVAL ? MONTH)
     ORDER BY snapshot_date ASC`,
    [req.userId, months]
  );
  const totals = await jobs.netWorthTotals(req.userId);
  const today = { snapshot_date: dates.toIsoDate(new Date()), ...totals };
  const list = [...rows, today];
  res.json({ evolution: list });
}));

router.post('/snapshot', asyncHandler(async (req, res) => {
  const snapshot = await jobs.snapshotNetWorth(req.userId);
  res.json({ snapshot });
}));

module.exports = router;
