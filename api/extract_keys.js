const ExcelJS = require('exceljs');
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '..', 'CONTROLE FINANCEIRO_2026_R1.xlsx');

async function extractKeySheets() {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(filePath);

  const result = {};

  const extract = (name, startRow, endRow, startCol, endCol) => {
    const ws = wb.getWorksheet(name);
    if (!ws) return { rows: [], note: 'sheet not found' };
    const rows = [];
    const sr = Math.max(1, startRow || 1);
    const er = Math.min(ws.rowCount, endRow || ws.rowCount);
    const sc = Math.max(1, startCol || 1);
    const ec = Math.min(ws.columnCount, endCol || ws.columnCount);
    for (let i = sr; i <= er; i++) {
      const row = ws.getRow(i);
      const cells = [];
      for (let j = sc; j <= ec; j++) {
        const cell = row.getCell(j);
        let v = cell.value;
        if (v === null || v === undefined) v = '';
        else if (typeof v === 'object') {
          if (v.formula) v = `=F(${v.formula})=${v.result ?? ''}`;
          else if (v.text) v = v.text;
          else if (v.result !== undefined) v = String(v.result);
          else v = JSON.stringify(v);
        } else v = String(v);
        cells.push(v);
      }
      if (cells.some(c => c.trim() !== '')) rows.push(cells);
    }
    return { rowCount: ws.rowCount, colCount: ws.columnCount, rows };
  };

  result.Jan_header = extract('Jan', 1, 8, 1, 27);
  result.Meta = extract('Meta', 1, 60, 1, 20);
  result.FC = extract('FC', 1, 60, 1, 20);
  result.DRE = extract('DRE', 1, 80, 1, 20);
  result.DRE_Detalhado = extract('DRE_Detalhado', 1, 60, 1, 15);
  result.Dash1 = extract('Dash1', 1, 50, 1, 20);
  result.Dash2 = extract('Dash2', 1, 50, 1, 20);
  result.Dash3 = extract('Dash3', 1, 50, 1, 20);
  result.Dash4 = extract('Dash4', 1, 50, 1, 20);
  result.Dash5 = extract('Dash5', 1, 50, 1, 20);
  result.Bancos = extract('Bancos', 1, 80, 1, 20);
  result.INI = extract('INI', 1, 50, 1, 25);
  result.FC_dia = extract('FC_dia', 1, 60, 1, 15);
  result.CP_CR = extract('CP_CR', 1, 60, 1, 20);
  result.Analise = extract('Analise', 1, 80, 1, 20);
  result.Imp = extract('Imp', 1, 60, 1, 20);
  result.Pgto = extract('Pgto', 1, 60, 1, 20);

  const out = path.join(__dirname, '..', 'key_sheets_extract.json');
  fs.writeFileSync(out, JSON.stringify(result, null, 2), 'utf8');
  console.log('Extraído em:', out);
}

extractKeySheets().catch(e => console.error(e));
