// Calculadoras financeiras (spec §39).
const express = require('express');
const { asyncHandler } = require('../middleware/errors');
const db = require('../db');
const dates = require('../lib/dates');

const router = express.Router();

function assertPositive(value, name) {
  if (value === undefined || Number(value) <= 0) throw Object.assign(new Error(`${name} deve ser maior que zero.`), { status: 400 });
}

function assertNonNegative(value, name) {
  if (Number(value) < 0) throw Object.assign(new Error(`${name} não pode ser negativo.`), { status: 400 });
}

// Juros compostos: M = P*(1+i)^n + PMT * (((1+i)^n - 1)/i)
router.post('/compound-interest', asyncHandler(async (req, res) => {
  const { principal = 0, monthly_contribution = 0, annual_rate, months } = req.body;
  if (months === undefined) throw Object.assign(new Error('months é obrigatório.'), { status: 400 });
  if (annual_rate < 0) throw Object.assign(new Error('annual_rate não pode ser negativo.'), { status: 400 });
  const i = Number(annual_rate) / 100 / 12;
  const n = Number(months);
  const p = Number(principal);
  const pmt = Number(monthly_contribution);
  const factor = Math.pow(1 + i, n);
  const futurePrincipal = p * factor;
  const futureContributions = i === 0 ? pmt * n : pmt * (factor - 1) / i;
  const final = futurePrincipal + futureContributions;
  const schedule = [];
  let balance = p;
  for (let m = 1; m <= Math.min(n, 600); m++) {
    const interest = balance * i;
    balance += interest + pmt;
    schedule.push({ month: m, contribution: pmt, interest: Number(interest.toFixed(2)), balance: Number(balance.toFixed(2)) });
  }
  res.json({ final: Number(final.toFixed(2)), total_contributions: pmt * n + p, total_interest: Number((final - (pmt * n + p)).toFixed(2)), schedule });
}));

router.post('/financing', asyncHandler(async (req, res) => {
  const { amount, annual_rate, months, system = 'price' } = req.body;
  assertPositive(amount, 'amount');
  if (months === undefined) throw Object.assign(new Error('months é obrigatório.'), { status: 400 });
  const i = Number(annual_rate) / 100 / 12;
  const n = Number(months);
  const schedule = [];
  let balance = Number(amount);
  if (system === 'price') {
    const pmt = i === 0 ? amount / n : amount * i / (1 - Math.pow(1 + i, -n));
    for (let k = 1; k <= n; k++) {
      const interest = balance * i;
      const amortization = pmt - interest;
      balance -= amortization;
      schedule.push({ number: k, payment: Number(pmt.toFixed(2)), interest: Number(interest.toFixed(2)), amortization: Number(amortization.toFixed(2)), balance: Number(Math.max(0, balance).toFixed(2)) });
    }
    const first = schedule[0].payment, last = schedule[0].payment;
    const total = first * n;
    res.json({ first_payment: first, last_payment: last, total_paid: Number(total.toFixed(2)), total_interest: Number((total - amount).toFixed(2)), schedule });
  } else {
    const amortization = amount / n;
    let total = 0;
    for (let k = 1; k <= n; k++) {
      const interest = balance * i;
      const payment = amortization + interest;
      balance -= amortization;
      total += payment;
      schedule.push({ number: k, payment: Number(payment.toFixed(2)), interest: Number(interest.toFixed(2)), amortization: Number(amortization.toFixed(2)), balance: Number(Math.max(0, balance).toFixed(2)) });
    }
    res.json({ first_payment: schedule[0].payment, last_payment: schedule[schedule.length - 1].payment, total_paid: Number(total.toFixed(2)), total_interest: Number((total - amount).toFixed(2)), schedule });
  }
}));

router.post('/loan', asyncHandler(async (req, res) => {
  const { amount, monthly_rate, months } = req.body;
  assertPositive(amount, 'amount');
  if (months === undefined) throw Object.assign(new Error('months é obrigatório.'), { status: 400 });
  const i = Number(monthly_rate) / 100;
  const n = Number(months);
  const pmt = i === 0 ? amount / n : amount * i / (1 - Math.pow(1 + i, -n));
  const total = pmt * n;
  const effectiveAnnual = Math.pow(1 + i, 12) - 1;
  res.json({ installment: Number(pmt.toFixed(2)), total_paid: Number(total.toFixed(2)), total_interest: Number((total - amount).toFixed(2)), effective_annual_rate: Number((effectiveAnnual * 100).toFixed(4)) });
}));

router.post('/investment-goal', asyncHandler(async (req, res) => {
  const { target_amount, months, annual_rate, monthly_contribution } = req.body;
  assertPositive(target_amount, 'target_amount');
  const i = Number(annual_rate || 0) / 100 / 12;
  if (monthly_contribution !== undefined) {
    // resolve meses: n = ln(1 + (FV*i)/(PMT)) / ln(1+i)
    let n = 0;
    if (monthly_contribution <= 0) n = Infinity;
    else if (i === 0) n = target_amount / monthly_contribution;
    else n = Math.log(1 + (target_amount * i) / monthly_contribution) / Math.log(1 + i);
    res.json({ months_needed: Number(n.toFixed(1)) });
  } else {
    if (months === undefined) throw Object.assign(new Error('months é obrigatório.'), { status: 400 });
    const n = Number(months);
    const pmt = i === 0 ? target_amount / n : target_amount * i / (Math.pow(1 + i, n) - 1);
    res.json({ monthly_contribution: Number(pmt.toFixed(2)) });
  }
}));

router.post('/emergency-reserve', asyncHandler(async (req, res) => {
  const { monthly_expenses, target_months, current_amount = 0, monthly_saving = 0 } = req.body;
  if (monthly_expenses === undefined || target_months === undefined) throw Object.assign(new Error('monthly_expenses e target_months são obrigatórios.'), { status: 400 });
  const recommended = Number(monthly_expenses) * Number(target_months);
  const remaining = Math.max(0, recommended - Number(current_amount));
  const months_to_target = Number(monthly_saving) > 0 ? remaining / Number(monthly_saving) : null;
  res.json({ recommended: Number(recommended.toFixed(2)), missing: Number(remaining.toFixed(2)), months_to_target: months_to_target ? Number(months_to_target.toFixed(1)) : null });
}));

router.get('/emergency-reserve/suggestion', asyncHandler(async (req, res) => {
  const [rows] = await db.query(
    `SELECT AVG(monthly) AS avg_expense FROM (
       SELECT SUM(amount) AS monthly FROM transactions
       WHERE user_id = ? AND type = 'expense' AND deleted_at IS NULL AND date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
       GROUP BY DATE_FORMAT(date, '%Y-%m')
     ) t`,
    [req.userId]
  );
  const monthly = Number(rows[0]?.avg_expense || 0);
  const suggestions = [3, 6, 9, 12].map(m => ({ months: m, reserve: Number((monthly * m).toFixed(2)) }));
  res.json({ monthly_expenses: monthly, suggestions });
}));

module.exports = router;
