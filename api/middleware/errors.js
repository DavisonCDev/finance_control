// Tratamento central de erros: registra em error_logs e responde JSON (spec §46).
const db = require('../db');

function notFound(req, res) {
  res.status(404).json({ error: `Rota não encontrada: ${req.method} ${req.originalUrl}` });
}

async function errorHandler(err, req, res, next) {
  const status = err.status || err.statusCode || 500;
  const message = err.message || 'Erro interno.';

  if (status >= 500) {
    console.error(`${req.method} ${req.originalUrl}:`, err);
    try {
      await db.query(
        `INSERT INTO error_logs (user_id, level, message, stack, route, method, status_code)
         VALUES (?, 'error', ?, ?, ?, ?, ?)`,
        [req.userId || null, message.slice(0, 500), err.stack || null, req.originalUrl?.slice(0, 180), req.method, status]
      );
    } catch (logErr) {
      console.error('error_logs:', logErr.message);
    }
  }

  if (res.headersSent) return next(err);
  res.status(status).json({ error: message });
}

// Envolve handlers async para que rejeições cheguem ao errorHandler.
function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

module.exports = { errorHandler, notFound, asyncHandler };
