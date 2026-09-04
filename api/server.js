require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const { errorHandler, notFound } = require('./middleware/errors');
const { startScheduler } = require('./lib/scheduler');

const app = express();

app.set('trust proxy', 1);
app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(compression());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use((req, res, next) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  next();
});

const routes = {
  '/auth': './routes/auth',
  '/me': './routes/profile',
  '/accounts': './routes/accounts',
  '/categories': './routes/categories',
  '/tags': './routes/tags',
  '/transactions': './routes/transactions',
  '/cards': './routes/cards',
  '/installments': './routes/installments',
  '/recurring': './routes/recurring',
  '/budgets': './routes/budgets',
  '/planning': './routes/planning',
  '/reports': './routes/reports',
  '/dashboard': './routes/dashboard',
  '/cashflow': './routes/cashflow',
  '/calendar': './routes/calendar',
  '/notifications': './routes/notifications',
  '/families': './routes/families',
  '/goals': './routes/goals',
  '/investments': './routes/investments',
  '/debts': './routes/debts',
  '/patrimony': './routes/patrimony',
  '/attachments': './routes/attachments',
  '/rules': './routes/rules',
  '/automations': './routes/automations',
  '/insights': './routes/insights',
  '/calculators': './routes/calculators',
  '/search': './routes/search',
  '/import-export': './routes/import_export',
  '/import-pdf': './routes/import_pdf',
  '/admin': './routes/admin',
  '/gamification': './routes/gamification',
  '/education': './routes/education',
  '/billing': './routes/billing',
  '/sync': './routes/sync',
  '/open-finance': './routes/openfinance',
  '/currencies': './routes/currencies',
};

for (const [path, modulePath] of Object.entries(routes)) {
  app.use(path, require(modulePath));
}

app.get('/', (req, res) => {
  res.json({
    message: 'Finance Control API em execução',
    version: require('./package.json').version,
    endpoints: Object.keys(routes),
  });
});

app.get('/health', async (req, res) => {
  const db = require('./db');
  try {
    await db.query('SELECT 1');
    res.json({ status: 'ok', database: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'degraded', database: err.message });
  }
});

app.use(notFound);
app.use(errorHandler);

const PORT = process.env.PORT || 3000;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Servidor Finance Control rodando na porta ${PORT}`);
    if (process.env.DISABLE_SCHEDULER !== 'true') startScheduler();
  });
}

module.exports = app;
