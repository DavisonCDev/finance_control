const pdfParse = require('pdf-parse');
console.log(typeof pdfParse);
const fs = require('fs');

const buffer = fs.readFileSync('c:\\Users\\davis\\Downloads\\itau_extrato_082026.pdf');

pdfParse(buffer).then(data => {
  const text = data.text;
  const lines = text.split('\n');
  const txs = [];

  for (let line of lines) {
    line = line.trim();
    if (!line || /saldo em conta|limite|extrato|período|data lançamentos|SALDO DO DIA|aviso!/i.test(line)) continue;

    const m = line.match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(.+?)\s+(-?\d{1,3}(?:\.\d{3})*,\d{2})\s*$/);
    if (m) {
      txs.push({
        date: `${m[1]}/${m[2]}/${m[3]}`,
        description: m[4].replace(/\s+/g, ' ').replace(/\d{2}\/\d{2}$/, '').trim(),
        amount: m[5]
      });
    }
  }

  console.log('Total:', txs.length);
  console.log(txs.slice(0, 10));
});
