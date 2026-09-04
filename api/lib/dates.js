// Helpers de data usados por recorrências, faturas, parcelas e relatórios.

const FREQUENCY_STEPS = {
  daily: { days: 1 },
  weekly: { days: 7 },
  biweekly: { days: 15 },
  monthly: { months: 1 },
  bimonthly: { months: 2 },
  quarterly: { months: 3 },
  semiannual: { months: 6 },
  yearly: { months: 12 },
};

function toIsoDate(date) {
  const d = date instanceof Date ? date : new Date(date);
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseDate(value) {
  if (value instanceof Date) return new Date(value.getFullYear(), value.getMonth(), value.getDate());
  const [year, month, day] = String(value).slice(0, 10).split('-').map(Number);
  return new Date(year, month - 1, day);
}

// Soma meses preservando o "último dia do mês" (31/01 + 1 mês = 28/02).
function addMonths(date, months) {
  const d = parseDate(date);
  const targetDay = d.getDate();
  const result = new Date(d.getFullYear(), d.getMonth() + months, 1);
  const lastDay = new Date(result.getFullYear(), result.getMonth() + 1, 0).getDate();
  result.setDate(Math.min(targetDay, lastDay));
  return result;
}

function addDays(date, days) {
  const d = parseDate(date);
  d.setDate(d.getDate() + days);
  return d;
}

function nextOccurrence(date, frequency) {
  const step = FREQUENCY_STEPS[frequency];
  if (!step) throw new Error(`Periodicidade inválida: ${frequency}`);
  return toIsoDate(step.days ? addDays(date, step.days) : addMonths(date, step.months));
}

function currentMonth() {
  return toIsoDate(new Date()).slice(0, 7);
}

function monthRange(month) {
  const [year, m] = month.split('-').map(Number);
  const start = new Date(year, m - 1, 1);
  const end = new Date(year, m, 0);
  return { start: toIsoDate(start), end: toIsoDate(end) };
}

function addMonthsToMonth(month, delta) {
  const [year, m] = month.split('-').map(Number);
  const d = new Date(year, m - 1 + delta, 1);
  return toIsoDate(d).slice(0, 7);
}

// Mês financeiro do usuário: se o ciclo começa no dia 5, 03/03 pertence a 2024-02.
function financialMonth(date, firstDayOfMonth = 1) {
  const d = parseDate(date);
  if (firstDayOfMonth > 1 && d.getDate() < firstDayOfMonth) {
    return toIsoDate(addMonths(d, -1)).slice(0, 7);
  }
  return toIsoDate(d).slice(0, 7);
}

function clampDay(year, monthIndex, day) {
  const lastDay = new Date(year, monthIndex + 1, 0).getDate();
  return Math.min(day || 1, lastDay);
}

// Descobre a qual fatura uma compra pertence e as datas de fechamento/vencimento.
// Compras a partir do dia de fechamento entram na fatura do mês seguinte.
function invoicePeriodFor(purchaseDate, closingDay, dueDay) {
  const d = parseDate(purchaseDate);
  let year = d.getFullYear();
  let monthIndex = d.getMonth();

  const closing = clampDay(year, monthIndex, closingDay);
  if (d.getDate() >= closing) monthIndex += 1;

  const closingDate = new Date(year, monthIndex, 1);
  closingDate.setDate(clampDay(closingDate.getFullYear(), closingDate.getMonth(), closingDay));

  // Vencimento cai no mês do fechamento, ou no seguinte quando due < closing.
  let dueMonthIndex = closingDate.getMonth();
  if ((dueDay || 1) < (closingDay || 1)) dueMonthIndex += 1;
  const dueDate = new Date(closingDate.getFullYear(), dueMonthIndex, 1);
  dueDate.setDate(clampDay(dueDate.getFullYear(), dueDate.getMonth(), dueDay));

  return {
    referenceMonth: toIsoDate(closingDate).slice(0, 7),
    closingDate: toIsoDate(closingDate),
    dueDate: toIsoDate(dueDate),
  };
}

function daysBetween(from, to) {
  const a = parseDate(from);
  const b = parseDate(to);
  return Math.round((b - a) / 86400000);
}

module.exports = {
  FREQUENCY_STEPS,
  toIsoDate,
  parseDate,
  addDays,
  addMonths,
  addMonthsToMonth,
  nextOccurrence,
  currentMonth,
  monthRange,
  financialMonth,
  invoicePeriodFor,
  daysBetween,
  clampDay,
};
