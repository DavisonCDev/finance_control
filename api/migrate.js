require('dotenv').config();
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const mysql = require('mysql2/promise');

const MIGRATIONS_DIR = path.join(__dirname, '../database/migrations');

// Erros que indicam que a alteração já existe no banco. Migrations aplicadas
// manualmente antes do controle de versão deixam o schema à frente dos arquivos,
// então tolerar esses códigos evita travar a esteira.
const IDEMPOTENT_ERRORS = new Set([
  'ER_DUP_FIELDNAME',
  'ER_DUP_KEYNAME',
  'ER_DUP_ENTRY',
  'ER_CANT_DROP_FIELD_OR_KEY',
  'ER_FK_DUP_NAME',
  'ER_TABLE_EXISTS_ERROR',
]);

// Divide o arquivo em statements respeitando strings, comentários e blocos
// DELIMITER (usados por triggers/procedures).
function splitStatements(sql) {
  const statements = [];
  let current = '';
  let quote = null;
  let i = 0;

  while (i < sql.length) {
    const char = sql[i];
    const next = sql[i + 1];

    if (quote) {
      current += char;
      if (char === '\\' && next) {
        current += next;
        i += 2;
        continue;
      }
      if (char === quote) quote = null;
      i++;
      continue;
    }

    if (char === "'" || char === '"' || char === '`') {
      quote = char;
      current += char;
      i++;
      continue;
    }

    if (char === '-' && next === '-') {
      const end = sql.indexOf('\n', i);
      i = end === -1 ? sql.length : end + 1;
      continue;
    }

    if (char === '/' && next === '*') {
      const end = sql.indexOf('*/', i);
      i = end === -1 ? sql.length : end + 2;
      continue;
    }

    if (char === ';') {
      if (current.trim()) statements.push(current.trim());
      current = '';
      i++;
      continue;
    }

    current += char;
    i++;
  }

  if (current.trim()) statements.push(current.trim());
  return statements;
}

async function ensureDatabase() {
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    charset: 'utf8mb4',
  });
  await connection.query(
    `CREATE DATABASE IF NOT EXISTS \`${process.env.DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
  );
  await connection.end();
}

async function ensureMigrationsTable(db) {
  await db.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id INT AUTO_INCREMENT PRIMARY KEY,
      filename VARCHAR(255) NOT NULL UNIQUE,
      checksum VARCHAR(64) NOT NULL,
      applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

async function migrate() {
  await ensureDatabase();

  const db = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    database: process.env.DB_NAME,
    charset: 'utf8mb4',
  });

  await ensureMigrationsTable(db);

  const [applied] = await db.query('SELECT filename, checksum FROM schema_migrations');
  const appliedMap = new Map(applied.map(r => [r.filename, r.checksum]));

  const files = fs.readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
  let count = 0;

  for (const file of files) {
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    const checksum = crypto.createHash('sha256').update(sql).digest('hex');

    if (appliedMap.has(file)) {
      if (appliedMap.get(file) !== checksum) {
        console.warn(`! ${file} foi alterada depois de aplicada (checksum diferente).`);
      }
      continue;
    }

    const statements = splitStatements(sql);
    let skipped = 0;

    for (const statement of statements) {
      try {
        await db.query(statement);
      } catch (err) {
        if (IDEMPOTENT_ERRORS.has(err.code)) {
          skipped++;
          continue;
        }
        console.error(`\nErro em ${file}:\n${statement.slice(0, 300)}\n`);
        throw err;
      }
    }

    await db.query('INSERT INTO schema_migrations (filename, checksum) VALUES (?, ?)', [file, checksum]);
    console.log(`+ ${file} (${statements.length} statements${skipped ? `, ${skipped} já existentes` : ''})`);
    count++;
  }

  console.log(count === 0 ? 'Banco já está atualizado.' : `${count} migration(s) aplicada(s).`);
  await db.end();
}

migrate().catch(err => {
  console.error(err.message);
  process.exit(1);
});
