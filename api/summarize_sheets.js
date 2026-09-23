const ExcelJS = require('exceljs');
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '..', 'CONTROLE FINANCEIRO_2026_R1.xlsx');

async function summarizeSpreadsheet() {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(filePath);
  
  const summary = {};
  
  const importantSheets = [
    'PC_Rec', 'PC_Des', 'PC_CC', 'PC_Banco', 'PC_Cli', 'PC_Transf',
    'Jan', 'Meta', 'FC', 'DRE', 'DRE_Detalhado', 'Bancos', 'Pgto',
    'Dash1', 'INI', 'Imp', 'FC_dia', 'CP_CR', 'Analise'
  ];
  
  for (const sheetName of importantSheets) {
    const ws = workbook.getWorksheet(sheetName);
    if (!ws) continue;
    
    const rows = [];
    const maxRows = Math.min(ws.rowCount, 80);
    const maxCols = Math.min(ws.columnCount, 20);
    
    for (let i = 1; i <= maxRows; i++) {
      const row = ws.getRow(i);
      const cells = [];
      for (let j = 1; j <= maxCols; j++) {
        const cell = row.getCell(j);
        let val = cell.value;
        if (val === null || val === undefined) val = '';
        else if (typeof val === 'object') {
          if (val.formula) val = `=FÓRMULA(${val.formula})`;
          else if (val.text) val = val.text;
          else if (val.result !== undefined) val = String(val.result);
          else val = JSON.stringify(val);
        } else {
          val = String(val);
        }
        cells.push(val);
      }
      if (cells.some(c => c.trim() !== '')) {
        rows.push(cells);
      }
    }
    summary[sheetName] = { rowCount: ws.rowCount, colCount: ws.columnCount, rows };
  }
  
  const out = path.join(__dirname, '..', 'spreadsheet_summary.json');
  fs.writeFileSync(out, JSON.stringify(summary, null, 2), 'utf8');
  console.log('Resumo salvo em:', out);
  console.log('Sheets resumidos:', Object.keys(summary).join(', '));
}

summarizeSpreadsheet().catch(e => console.error(e));
