// Popula dados de referência. NÃO destrói dados: rode `node migrate.js` antes.
// As categorias, moedas, planos, conquistas e conteúdos padrão já vêm das migrations;
// este script cria dados de demonstração para um usuário existente.
require('dotenv').config();
const bcrypt = require('bcryptjs');
const mysql = require('mysql2/promise');

const DEMO_EMAIL = process.env.SEED_EMAIL || 'demo@financecontrol.local';
const DEMO_PASSWORD = process.env.SEED_PASSWORD || 'demo1234';

async function seed() {
  const db = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    database: process.env.DB_NAME,
    charset: 'utf8mb4',
  });

  const [migrations] = await db.query(
    "SELECT COUNT(*) n FROM information_schema.tables WHERE table_schema = ? AND table_name = 'schema_migrations'",
    [process.env.DB_NAME]
  );
  if (migrations[0].n === 0) {
    console.error('Banco não migrado. Execute: node migrate.js');
    process.exit(1);
  }

  let [users] = await db.query('SELECT id FROM users WHERE email = ?', [DEMO_EMAIL]);
  if (users.length === 0) {
    const hash = await bcrypt.hash(DEMO_PASSWORD, 10);
    const [result] = await db.query(
      'INSERT INTO users (name, email, password_hash, email_verified) VALUES (?, ?, ?, TRUE)',
      ['Usuário Demo', DEMO_EMAIL, hash]
    );
    users = [{ id: result.insertId }];
    console.log(`+ usuário demo criado: ${DEMO_EMAIL} / ${DEMO_PASSWORD}`);
  }

  const userId = users[0].id;

  const [accounts] = await db.query('SELECT COUNT(*) n FROM accounts WHERE user_id = ?', [userId]);
  if (accounts[0].n === 0) {
    await db.query(
      `INSERT INTO accounts (user_id, name, type, initial_balance, current_balance) VALUES
        (?, 'Conta corrente', 'checking', 5000, 5000),
        (?, 'Carteira', 'cash', 300, 300),
        (?, 'Poupança', 'savings', 12000, 12000)`,
      [userId, userId, userId]
    );
    console.log('+ contas de demonstração criadas');
  }

  const [cards] = await db.query('SELECT COUNT(*) n FROM credit_cards WHERE user_id = ?', [userId]);
  if (cards[0].n === 0) {
    await db.query(
      `INSERT INTO credit_cards (user_id, name, bank, brand, limit_amount, closing_day, due_day, holder_name)
       VALUES (?, 'Cartão principal', 'Itaú', 'Visa', 8000, 25, 5, 'Usuário Demo')`,
      [userId]
    );
    console.log('+ cartão de demonstração criado');
  }

  // Preferências de notificação padrão
  const types = [
    'bill_due', 'card_due', 'invoice_closed', 'budget_near', 'budget_over',
    'low_balance', 'installment_due', 'income_missing', 'family_expense', 'insight',
  ];
  for (const type of types) {
    await db.query(
      'INSERT IGNORE INTO notification_preferences (user_id, type) VALUES (?, ?)',
      [userId, type]
    );
  }

  await db.query('INSERT IGNORE INTO user_streaks (user_id) VALUES (?)', [userId]);
  await db.query(
    'INSERT IGNORE INTO subscriptions (user_id, plan_code, status, started_at) VALUES (?, ?, ?, NOW())',
    [userId, 'free', 'active']
  );

  console.log('Seed concluído.');
  await db.end();
}

seed().catch(err => {
  console.error(err.message);
  process.exit(1);
});
