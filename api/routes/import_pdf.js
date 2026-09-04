const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const PDFParser = require('pdf2json');
const db = require('../db');
const authenticate = require('../middleware/auth');
const router = express.Router();

const upload = multer({ dest: path.join(__dirname, '../uploads/') });

const categoryKeywords = {
  1: ['remuneracao', 'salario', 'pagamento'],
  2: ['freelance', 'projeto'],
  3: ['investimento', 'rendimento'],
  4: ['transferencia recebida', 'pix recebido', 'ted creditado'],
  5: ['aluguel', 'condominio', 'moradia'],
  6: ['ifood', 'mercado', 'supermercado', 'padaria', 'restaurante', 'lanche', 'pizza'],
  7: ['uber', '99', 'transporte', 'combustivel', 'posto', 'pedagio'],
  8: ['cinema', 'lazer', 'show', 'viagem'],
  9: ['farmacia', 'hospital', 'medico', 'saude', 'droga'],
  10: ['escola', 'faculdade', 'curso', 'educacao', 'material escolar'],
  11: ['energia', 'agua', 'internet', 'telefone', 'tim', 'seguro', 'fatura', 'iof', 'juros'],
  12: ['compra', 'shopping', 'market', 'pay', 'credito consignado'],
  13: ['crediario', 'outras', 'saque', 'pix transf'],
};

function classifyCategory(description) {
  const lower = description.toLowerCase();
  for (const [catId, keywords] of Object.entries(categoryKeywords)) {
    if (keywords.some(k => lower.includes(k))) return parseInt(catId);
  }
  return null;
}

function cleanDescription(desc) {
  return desc
    .replace(/\s+/g, ' ')
    .replace(/\d{2}\/\d{2}$/, '')
    .replace(/\d{2}\/\d{2}\/\d{4}$/, '')
    .trim();
}

async function getUserCategories(userId) {
  const [rows] = await db.query(
    'SELECT id, name FROM categories WHERE user_id = ? OR user_id IS NULL ORDER BY name',
    [userId]
  );
  return rows;
}

function parseItauStatement(text) {
  const transactions = [];
  const lines = text.split(/\r?\n/);

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    if (
      !line ||
      /saldo em conta|limite da conta|extrato conta|período de visualização|data lançamentos|aviso!/i.test(line) ||
      /SALDO DO DIA|DAVISON CAMPOS/i.test(line)
    ) {
      continue;
    }

    const match = line.match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(.+?)\s+(-?\d{1,3}(?:\.\d{3})*,\d{2})\s*$/);
    if (match) {
      const [_, day, month, year, rawDescription, amountStr] = match;
      const amount = parseFloat(amountStr.replace(/\./g, '').replace(',', '.'));
      const description = cleanDescription(rawDescription);
      const type = amount < 0 ? 'expense' : 'income';
      const categoryId = type === 'expense' ? classifyCategory(description) : null;

      transactions.push({
        date: `${year}-${month}-${day}`,
        description,
        amount: Math.abs(amount),
        type,
        suggested_category_id: categoryId,
      });
    }
  }

  return transactions;
}

function parsePdfBuffer(buffer) {
  return new Promise((resolve, reject) => {
    const pdfParser = new PDFParser(this, 1);

    pdfParser.on('pdfParser_dataError', errData => reject(errData.parserError));
    pdfParser.on('pdfParser_dataReady', () => {
      resolve(pdfParser.getRawTextContent());
    });

    pdfParser.parseBuffer(buffer);
  });
}

router.post('/', authenticate, upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Arquivo não enviado.' });

  try {
    const buffer = fs.readFileSync(req.file.path);
    const text = await parsePdfBuffer(buffer);
    const parsed = parseItauStatement(text);
    const categories = await getUserCategories(req.userId);

    fs.unlinkSync(req.file.path);

    res.json({
      transactions: parsed,
      categories,
    });
  } catch (err) {
    if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
    res.status(500).json({ error: err.message || 'Erro ao processar PDF.' });
  }
});

router.post('/import', authenticate, async (req, res) => {
  const { account_id, category_id, transactions } = req.body;
  if (!account_id || !Array.isArray(transactions)) {
    return res.status(400).json({ error: 'Conta e transações são obrigatórios.' });
  }

  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    const imported = [];
    for (const t of transactions) {
      const catId = t.category_id || t.suggested_category_id || category_id;
      const [result] = await connection.query(
        'INSERT INTO transactions (user_id, account_id, category_id, type, amount, date, description) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [req.userId, account_id, catId, t.type, t.amount, t.date, t.description]
      );

      const factor = t.type === 'income' ? 1 : -1;
      await connection.query(
        'UPDATE accounts SET current_balance = current_balance + ? WHERE id = ? AND user_id = ?',
        [t.amount * factor, account_id, req.userId]
      );
      imported.push(result.insertId);
    }
    await connection.commit();
    res.json({ imported, count: imported.length });
  } catch (err) {
    await connection.rollback();
    res.status(500).json({ error: err.message });
  } finally {
    connection.release();
  }
});

module.exports = router;
