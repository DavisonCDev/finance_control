const fs = require('fs');
const PDFParser = require('pdf2json');

const buffer = fs.readFileSync('c:\\Users\\davis\\Downloads\\itau_extrato_082026.pdf');
const pdfParser = new PDFParser(this, 1);

pdfParser.on('pdfParser_dataError', err => console.error(err.parserError));
pdfParser.on('pdfParser_dataReady', () => {
  const text = pdfParser.getRawTextContent();
  const lines = text.split(/\r?\n/);
  const txs = [];

  for (let line of lines) {
    line = line.trim();
    if (!line || /saldo em conta|limite|extrato|período|data lançamentos|SALDO DO DIA|aviso!|DAVISON CAMPOS/i.test(line)) continue;

    const m = line.match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(.+?)\s+(-?\d{1,3}(?:\.\d{3})*,\d{2})\s*$/);
    if (m) {
      const amount = parseFloat(m[5].replace(/\./g, '').replace(',', '.'));
      txs.push({
        date: `${m[3]}-${m[2]}-${m[1]}`,
        description: m[4].replace(/\s+/g, ' ').replace(/\d{2}\/\d{2}$/, '').trim(),
        amount: Math.abs(amount),
        type: amount < 0 ? 'expense' : 'income'
      });
    }
  }

  console.log('Total:', txs.length);
  console.log(txs.slice(0, 15));
});

pdfParser.parseBuffer(buffer);
