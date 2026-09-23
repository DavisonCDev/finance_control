const db = require('../db');

async function getCashFlow(userId, month, filters = {}) {
  const params = [userId, month];
  let sql = `
    SELECT
      t.type,
      c.name AS category_name,
      a.name AS bank_name,
      cc.name AS cost_center_name,
      co.name AS contact_name,
      SUM(t.amount) AS total
    FROM transactions t
    LEFT JOIN categories c ON c.id = t.category_id
    LEFT JOIN accounts a ON a.id = t.account_id
    LEFT JOIN cost_centers cc ON cc.id = t.cost_center_id
    LEFT JOIN contacts co ON co.id = t.contact_id
    WHERE t.user_id = ?
      AND t.deleted_at IS NULL
      AND DATE_FORMAT(t.payment_date, '%Y-%m') = ?
      AND t.is_paid = TRUE
      AND t.type IN ('income', 'expense')
  `;

  if (filters.bankAccountId) {
    sql += ' AND t.account_id = ?';
    params.push(filters.bankAccountId);
  }
  if (filters.costCenterId) {
    sql += ' AND t.cost_center_id = ?';
    params.push(filters.costCenterId);
  }

  sql += ' GROUP BY t.type, c.name, a.name, cc.name, co.name';

  const [rows] = await db.query(sql, params);
  const income = rows
    .filter(r => r.type === 'income')
    .reduce((s, r) => s + Number(r.total), 0);
  const expense = rows
    .filter(r => r.type === 'expense')
    .reduce((s, r) => s + Number(r.total), 0);

  return {
    month,
    regime: 'cash',
    income,
    expense,
    net: income - expense,
    items: rows,
  };
}

async function getDRE(userId, month, filters = {}) {
  const params = [userId, month];
  let sql = `
    SELECT
      t.type,
      c.name AS category_name,
      cc.name AS cost_center_name,
      co.name AS contact_name,
      SUM(t.amount) AS total
    FROM transactions t
    LEFT JOIN categories c ON c.id = t.category_id
    LEFT JOIN cost_centers cc ON cc.id = t.cost_center_id
    LEFT JOIN contacts co ON co.id = t.contact_id
    WHERE t.user_id = ?
      AND t.deleted_at IS NULL
      AND DATE_FORMAT(t.accrual_date, '%Y-%m') = ?
      AND t.type IN ('income', 'expense')
  `;

  if (filters.costCenterId) {
    sql += ' AND t.cost_center_id = ?';
    params.push(filters.costCenterId);
  }

  sql += ' GROUP BY t.type, c.name, cc.name, co.name';

  const [rows] = await db.query(sql, params);
  const income = rows
    .filter(r => r.type === 'income')
    .reduce((s, r) => s + Number(r.total), 0);
  const expense = rows
    .filter(r => r.type === 'expense')
    .reduce((s, r) => s + Number(r.total), 0);

  return {
    month,
    regime: 'accrual',
    income,
    expense,
    net: income - expense,
    items: rows,
  };
}

async function getDashboard(userId, month) {
  const dre = await getDRE(userId, month);
  const cash = await getCashFlow(userId, month);

  const profitability = dre.income > 0
    ? Number(((dre.net / dre.income) * 100).toFixed(2))
    : 0;

  const [balance] = await db.query(
    'SELECT COALESCE(SUM(current_balance), 0) AS total FROM accounts WHERE user_id = ? AND active = TRUE',
    [userId]
  );

  return {
    month,
    profit: dre.net,
    profitability,
    income: { accrual: dre.income, cash: cash.income },
    expense: { accrual: dre.expense, cash: cash.expense },
    balance: Number(balance[0].total),
  };
}

async function updateBankBalanceOnPayment(transactionId, userId) {
  const [rows] = await db.query(
    `SELECT t.account_id, t.type, t.amount, t.is_paid, a.current_balance
     FROM transactions t
     JOIN accounts a ON a.id = t.account_id
     WHERE t.id = ? AND t.user_id = ? AND t.deleted_at IS NULL`,
    [transactionId, userId]
  );
  if (!rows.length) return;

  const t = rows[0];
  if (!t.is_paid || !t.account_id || t.type === 'transfer') return;

  const sign = { income: 1, expense: -1, adjustment: 1 }[t.type] || 0;
  const newBalance = Number(t.current_balance) + (Number(t.amount) * sign);

  await db.query(
    'UPDATE accounts SET current_balance = ? WHERE id = ? AND user_id = ?',
    [newBalance, t.account_id, userId]
  );
}

// ============================================================
// ANUAL: Fluxo de Caixa (FC sheet) - 12 meses + Total
// Campos: Saldo Inicial, Receitas pagas, Despesas pagas,
// Lucro/Prejuizo, Acumulado, Lucratividade %,
// Contas a Receber, Contas a Pagar, Nec. de Caixa
// ============================================================
async function getYearlyCashFlow(userId, year) {
  const [balanceRows] = await db.query(
    `SELECT COALESCE(SUM(initial_balance), 0) as initial_total
     FROM accounts WHERE user_id = ? AND active = TRUE`,
    [userId]
  );
  const initialBalance = Number(balanceRows[0].initial_total || 0);

  const [txPaidRows] = await db.query(
    `SELECT
       MONTH(t.payment_date) AS m,
       t.type,
       SUM(t.amount) AS total
     FROM transactions t
     WHERE t.user_id = ? AND t.deleted_at IS NULL
       AND YEAR(t.payment_date) = ?
       AND t.is_paid = TRUE
       AND t.type IN ('income','expense')
     GROUP BY MONTH(t.payment_date), t.type`,
    [userId, year]
  );

  const [accrualPaidRows] = await db.query(
    `SELECT
       MONTH(t.accrual_date) AS m,
       t.type,
       t.is_paid,
       SUM(t.amount) AS total
     FROM transactions t
     WHERE t.user_id = ? AND t.deleted_at IS NULL
       AND YEAR(t.accrual_date) = ?
       AND t.type IN ('income','expense')
     GROUP BY MONTH(t.accrual_date), t.type, t.is_paid`,
    [userId, year]
  );

  const paidIncome  = Array(13).fill(0);
  const paidExpense = Array(13).fill(0);
  txPaidRows.forEach(r => {
    const m = Number(r.m);
    if (m < 1 || m > 12) return;
    if (r.type === 'income')  paidIncome[m]  += Number(r.total);
    if (r.type === 'expense') paidExpense[m] += Number(r.total);
  });
  paidIncome[0]  = paidIncome.slice(1,13).reduce((a,b)=>a+b,0);
  paidExpense[0] = paidExpense.slice(1,13).reduce((a,b)=>a+b,0);

  const receivable = Array(13).fill(0);
  const payable    = Array(13).fill(0);
  accrualPaidRows.forEach(r => {
    const m = Number(r.m);
    if (m < 1 || m > 12) return;
    if (!r.is_paid) {
      if (r.type === 'income')  receivable[m] += Number(r.total);
      if (r.type === 'expense') payable[m]    += Number(r.total);
    }
  });
  receivable[0] = receivable.slice(1,13).reduce((a,b)=>a+b,0);
  payable[0]    = payable.slice(1,13).reduce((a,b)=>a+b,0);

  const months = [];
  let runningBalance = initialBalance;
  for (let m = 1; m <= 12; m++) {
    const profit = paidIncome[m] - paidExpense[m];
    runningBalance += profit;
    const profitability = paidIncome[m] > 0
      ? Number(((profit / paidIncome[m]) * 100).toFixed(2)) : 0;
    months.push({
      month: m,
      initial_balance: m === 1 ? initialBalance
        : (runningBalance - profit),
      income_paid: Number(paidIncome[m].toFixed(2)),
      expense_paid: Number(paidExpense[m].toFixed(2)),
      profit: Number(profit.toFixed(2)),
      accumulated: Number(runningBalance.toFixed(2)),
      profitability,
      accounts_receivable: Number(receivable[m].toFixed(2)),
      accounts_payable: Number(payable[m].toFixed(2)),
      cash_need: Number((receivable[m] - payable[m]).toFixed(2)),
    });
  }
  const total = months[months.length - 1];
  return { year, months, total };
}

// ============================================================
// ANUAL: DRE completo com 9 linhas x 12 meses (DRE sheet)
// ============================================================
const DRE_LINES = [
  { key: 'receitas_operacionais', label: 'Receitas', sign: +1, groups: ['Receita1','Receita2','Receita3','Receita4'] },
  { key: 'custos',               label: '(-) Despesas variáveis', sign: -1, groups: ['Custo1','Custo2','Custo3'] },
  { key: 'margem_contribuicao',  label: 'Saldo após despesas variáveis', type: 'calc', formula: 'receitas_operacionais + custos' },
  { key: 'despesas',             label: '(-) Despesas fixas e extras', sign: -1, groups: ['Despesa1','Despesa2','Despesa3','Despesa4','Despesa5'] },
  { key: 'resultado_financeiro', label: 'Resultado financeiro',    sign: +1, groups: [] },
  { key: 'impostos',             label: '(-) Impostos',            sign: -1, groups: ['Imposto'] },
  { key: 'lucro_prejuizo',       label: 'Resultado do mês',        type: 'calc', formula: 'margem_contribuicao + despesas + resultado_financeiro + impostos' },
  { key: 'investimentos',        label: '(-) Investimentos',       sign: -1, groups: ['Investimento'] },
  { key: 'ebtida',               label: 'Saldo final',             type: 'calc', formula: 'lucro_prejuizo + investimentos' },
];

async function getYearlyDRE(userId, year) {
  const [groupRows] = await db.query(
    `SELECT
       MONTH(t.accrual_date) AS m,
       c.pc_group,
       SUM(t.amount) AS total
     FROM transactions t
     LEFT JOIN categories c ON c.id = t.category_id
     WHERE t.user_id = ? AND t.deleted_at IS NULL
       AND YEAR(t.accrual_date) = ?
       AND t.type IN ('income','expense')
       AND c.pc_group IS NOT NULL
     GROUP BY MONTH(t.accrual_date), c.pc_group`,
    [userId, year]
  );

  const byGroupMonth = {};
  groupRows.forEach(r => {
    const m = Number(r.m);
    if (m < 1 || m > 12) return;
    byGroupMonth[r.pc_group] = byGroupMonth[r.pc_group] || Array(13).fill(0);
    byGroupMonth[r.pc_group][m] += Number(r.total);
  });

  const lines = DRE_LINES.map(line => {
    const perMonth = Array(13).fill(0);
    if (line.type === 'calc') {
      for (let m = 1; m <= 12; m++) {
        perMonth[m] = 0;
      }
      perMonth[0] = 0;
    } else {
      for (let m = 1; m <= 12; m++) {
        let v = 0;
        (line.groups || []).forEach(g => {
          if (byGroupMonth[g]) v += byGroupMonth[g][m] || 0;
        });
        perMonth[m] = Number((v * (line.sign || 1)).toFixed(2));
      }
      perMonth[0] = Number(perMonth.slice(1,13).reduce((a,b)=>a+b,0).toFixed(2));
    }
    return { key: line.key, label: line.label, per_month: perMonth, is_calc: !!line.type };
  });

  for (let m = 1; m <= 12; m++) {
    lines.find(l=>l.key==='margem_contribuicao').per_month[m] = Number(
      (lines.find(l=>l.key==='receitas_operacionais').per_month[m] +
       lines.find(l=>l.key==='custos').per_month[m]).toFixed(2)
    );
    lines.find(l=>l.key==='lucro_prejuizo').per_month[m] = Number(
      (lines.find(l=>l.key==='margem_contribuicao').per_month[m] +
       lines.find(l=>l.key==='despesas').per_month[m] +
       lines.find(l=>l.key==='resultado_financeiro').per_month[m] +
       lines.find(l=>l.key==='impostos').per_month[m]).toFixed(2)
    );
    lines.find(l=>l.key==='ebtida').per_month[m] = Number(
      (lines.find(l=>l.key==='lucro_prejuizo').per_month[m] +
       lines.find(l=>l.key==='investimentos').per_month[m]).toFixed(2)
    );
  }
  lines.forEach(l => {
    if (l.is_calc) l.per_month[0] = Number(l.per_month.slice(1,13).reduce((a,b)=>a+b,0).toFixed(2));
  });

  return { year, lines };
}

// ============================================================
// ANUAL: DRE Detalhado por grupo (DRE_Detalhado sheet)
// ============================================================
async function getDREDetailed(userId, year, pcGroup = null, parentCode = null) {
  const params = [userId, year, userId];
  let pcWhere = 'c.pc_group IS NOT NULL';
  if (pcGroup) { pcWhere = 'c.pc_group = ?'; params.push(pcGroup); }
  if (parentCode) {
    pcWhere += ' AND c.pc_code LIKE ?';
    params.push(parentCode + '%');
  }

  const sql = `
    SELECT
      c.id AS category_id,
      c.name,
      c.pc_code,
      c.pc_group,
      MONTH(t.accrual_date) AS m,
      COALESCE(SUM(t.amount), 0) AS total
    FROM categories c
    LEFT JOIN transactions t
      ON t.category_id = c.id
     AND t.user_id = ?
     AND t.deleted_at IS NULL
     AND YEAR(t.accrual_date) = ?
     AND t.type IN ('income','expense')
    WHERE (c.user_id IS NULL OR c.user_id = ?)
      AND ${pcWhere}
    GROUP BY c.id, c.name, c.pc_code, c.pc_group, MONTH(t.accrual_date)
    ORDER BY c.pc_code, c.name
  `;
  const [rows] = await db.query(sql, params);
  const agg = {};
  rows.forEach(r => {
    const key = r.category_id;
    if (!agg[key]) {
      agg[key] = {
        category_id: r.category_id,
        name: r.name,
        pc_code: r.pc_code,
        pc_group: r.pc_group,
        per_month: Array(13).fill(0),
      };
    }
    const m = Number(r.m);
    if (m >= 1 && m <= 12) {
      agg[key].per_month[m] = Number(Number(r.total).toFixed(2));
    }
  });
  const items = Object.values(agg);
  items.forEach(it => {
    it.per_month[0] = Number(it.per_month.slice(1,13).reduce((a,b)=>a+b,0).toFixed(2));
  });
  return { year, pc_group: pcGroup, items };
}

// ============================================================
// METAS MENSAIS (Meta sheet)
// ============================================================
async function getMonthlyGoals(userId, year) {
  const [metaRows] = await db.query(
    `SELECT * FROM goals_monthly WHERE user_id = ? AND year = ?`,
    [userId, year]
  );

  const [actualRows] = await db.query(
    `SELECT
       MONTH(t.accrual_date) AS m,
       t.type,
       SUM(t.amount) AS total
     FROM transactions t
     WHERE t.user_id = ? AND t.deleted_at IS NULL
       AND YEAR(t.accrual_date) = ?
       AND t.type IN ('income','expense')
     GROUP BY MONTH(t.accrual_date), t.type`,
    [userId, year]
  );

  const actualIncome = Array(12).fill(0);
  const actualExpense = Array(12).fill(0);
  actualRows.forEach(r => {
    const m = Number(r.m) - 1;
    if (m < 0 || m > 11) return;
    if (r.type === 'income')  actualIncome[m]  += Number(r.total);
    if (r.type === 'expense') actualExpense[m] += Number(r.total);
  });
  const actualResult = actualIncome.map((v,i)=> v - actualExpense[i]);

  const findGoal = (t) => metaRows.find(m => m.goal_type === t);
  const monthsLabel = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];

  const buildBlock = (goalType, actualArr) => {
    const g = findGoal(goalType);
    const targets = Array.from({length:12}, (_,i)=> g ? Number(g['month_' + (i+1)]) : 0);
    const realized = actualArr;
    const totalTarget = targets.reduce((a,b)=>a+b,0);
    const totalRealized = realized.reduce((a,b)=>a+b,0);
    const monthsWithActivity = realized.filter(v=> v > 0).length;
    const parcialTarget    = monthsWithActivity > 0 ? (targets.reduce((s,v,i)=> realized[i]>0 ? s+v : s,0)) : 0;
    const parcialRealized  = monthsWithActivity > 0 ? (realized.reduce((s,v)=> v>0 ? s+v : s,0)) : 0;

    const months = [];
    for (let i = 0; i < 12; i++) {
      const dif = targets[i] > 0 ? (((realized[i] - targets[i]) / targets[i]) * 100) : 0;
      months.push({
        month: i + 1,
        label: monthsLabel[i],
        target: Number(targets[i].toFixed(2)),
        realized: Number(realized[i].toFixed(2)),
        difference_percent: Number(dif.toFixed(2)),
      });
    }
    return {
      goal_type: goalType,
      months,
      total: {
        target: Number(totalTarget.toFixed(2)),
        realized: Number(totalRealized.toFixed(2)),
        difference_percent: totalTarget > 0
          ? Number((((totalRealized - totalTarget) / totalTarget) * 100).toFixed(2)) : 0,
      },
      parcial: {
        months_active: monthsWithActivity,
        target: Number(parcialTarget.toFixed(2)),
        realized: Number(parcialRealized.toFixed(2)),
        difference_percent: parcialTarget > 0
          ? Number((((parcialRealized - parcialTarget) / parcialTarget) * 100).toFixed(2)) : 0,
      },
    };
  };

  return {
    year,
    receitas:   buildBlock('receita',   actualIncome),
    despesas:   buildBlock('despesa',   actualExpense),
    resultado:  buildBlock('resultado', actualResult),
  };
}

async function upsertMonthlyGoals(userId, year, goalType, months) {
  const cols = [];
  const vals = [];
  const placeholders = [];
  cols.push('user_id','year','goal_type');
  placeholders.push('?','?','?');
  vals.push(userId, year, goalType);
  for (let i = 1; i <= 12; i++) {
    cols.push('month_' + i);
    placeholders.push('?');
    vals.push(Number(months[i-1] || 0));
  }
  const updCols = cols.slice(3).map(c => c + ' = VALUES(' + c + ')').join(', ');
  const sql = `INSERT INTO goals_monthly (${cols.join(',')}) VALUES (${placeholders.join(',')})
               ON DUPLICATE KEY UPDATE ${updCols}`;
  await db.query(sql, vals);
  return getMonthlyGoals(userId, year);
}

module.exports = {
  getCashFlow,
  getDRE,
  getDashboard,
  updateBankBalanceOnPayment,
  getYearlyCashFlow,
  getYearlyDRE,
  getDREDetailed,
  getMonthlyGoals,
  upsertMonthlyGoals,
};
