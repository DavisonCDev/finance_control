// Agendador de rotinas automáticas (spec §35).
// Roda dentro do processo da API; para ambientes com múltiplas instâncias,
// defina DISABLE_SCHEDULER=true e chame os endpoints /automations/run externamente.
const cron = require('node-cron');
const jobs = require('./jobs');

const TIMEZONE = process.env.SCHEDULER_TZ || 'America/Sao_Paulo';

async function run(name, fn) {
  const startedAt = Date.now();
  try {
    const result = await fn();
    console.log(`[scheduler] ${name}: ${JSON.stringify(result)} (${Date.now() - startedAt}ms)`);
  } catch (err) {
    console.error(`[scheduler] ${name} falhou:`, err.message);
  }
}

function startScheduler() {
  // 00:10 — gera recorrências vencidas e fecha faturas do dia
  cron.schedule('10 0 * * *', async () => {
    await run('recorrências', () => jobs.runDueRecurring());
    await run('faturas', () => jobs.closeDueInvoices());
    await run('parcelas', () => jobs.markDueInstallments());
  }, { timezone: TIMEZONE });

  // 08:00 — varredura de alertas financeiros
  cron.schedule('0 8 * * *', async () => {
    await run('notificações', () => jobs.scanNotifications());
  }, { timezone: TIMEZONE });

  // 09:00 — insights, assinaturas detectadas e automações do usuário
  cron.schedule('0 9 * * *', async () => {
    await run('assinaturas', () => jobs.detectSubscriptions());
    await run('insights', () => jobs.generateInsights());
    await run('automações', () => jobs.runDueAutomations());
  }, { timezone: TIMEZONE });

  // Dia 1º às 01:00 — fotografia do patrimônio
  cron.schedule('0 1 1 * *', async () => {
    await run('patrimônio', () => jobs.snapshotNetWorth());
  }, { timezone: TIMEZONE });

  console.log(`[scheduler] ativo (${TIMEZONE})`);
}

module.exports = { startScheduler, run };
