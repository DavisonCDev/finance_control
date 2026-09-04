// Utilitário de inspeção: lista tabelas, colunas e contagens do banco atual.
// Uso: node tools/inspect_db.js [tabela...]
require('dotenv').config();
const mysql = require('mysql2/promise');

async function main() {
  const db = await mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    database: process.env.DB_NAME,
  });

  const [tableRows] = await db.query('SHOW TABLES');
  const tables = tableRows.map(r => Object.values(r)[0]);
  const filter = process.argv.slice(2);

  console.log(`${tables.length} tabelas: ${tables.join(', ')}\n`);

  for (const table of filter.length ? filter : []) {
    const [cols] = await db.query(`SHOW COLUMNS FROM \`${table}\``);
    console.log(`${table}:\n  ${cols.map(c => c.Field).join(', ')}\n`);
  }

  for (const table of tables) {
    const [[{ n }]] = await db.query(`SELECT COUNT(*) n FROM \`${table}\``);
    if (n > 0) console.log(`  ${table}: ${n} registro(s)`);
  }

  await db.end();
}

main().catch(err => {
  console.error(err.message);
  process.exit(1);
});
