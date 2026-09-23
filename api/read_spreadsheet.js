const ExcelJS = require('exceljs');
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '..', 'CONTROLE FINANCEIRO_2026_R1.xlsx');

async function readSpreadsheet() {
  try {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.readFile(filePath);
    
    const result = {
      sheets: [],
      data: {}
    };
    
    workbook.eachSheet((worksheet, sheetId) => {
      result.sheets.push(worksheet.name);
      const rows = [];
      const maxCols = Math.min(worksheet.columnCount || 30, 30);
      const maxRows = Math.min(worksheet.rowCount || 200, 200);
      
      for (let i = 1; i <= maxRows; i++) {
        const row = worksheet.getRow(i);
        const rowData = [];
        for (let j = 1; j <= maxCols; j++) {
          const cell = row.getCell(j);
          let value = cell.value;
          if (value === null || value === undefined) {
            rowData.push('');
          } else if (typeof value === 'object') {
            if (value.result !== undefined) {
              rowData.push(String(value.result));
            } else if (value.text !== undefined) {
              rowData.push(value.text);
            } else {
              rowData.push(JSON.stringify(value));
            }
          } else {
            rowData.push(String(value));
          }
        }
        rows.push(rowData);
      }
      result.data[worksheet.name] = rows;
    });
    
    const outputPath = path.join(__dirname, '..', 'spreadsheet_content.json');
    fs.writeFileSync(outputPath, JSON.stringify(result, null, 2), 'utf8');
    console.log('Arquivo gerado com sucesso:', outputPath);
    console.log('Planilhas encontradas:', result.sheets.join(', '));
  } catch (err) {
    console.error('Erro ao ler planilha:', err.message);
    console.error(err.stack);
    process.exit(1);
  }
}

readSpreadsheet();
