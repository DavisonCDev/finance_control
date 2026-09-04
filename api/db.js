require('dotenv').config();
const mysql = require('mysql2/promise');

const db = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  database: process.env.DB_NAME,
  charset: 'utf8mb4',
  // Devolve DATE/DATETIME como string: evita o deslocamento de fuso que fazia
  // um lançamento do dia 01 virar dia 30 do mês anterior no JSON.
  dateStrings: ['DATE', 'DATETIME'],
  decimalNumbers: true,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// Executa uma função dentro de uma transação, liberando a conexão sempre.
async function withTransaction(handler) {
  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    const result = await handler(connection);
    await connection.commit();
    return result;
  } catch (err) {
    await connection.rollback();
    throw err;
  } finally {
    connection.release();
  }
}

module.exports = db;
module.exports.withTransaction = withTransaction;
