-- Renomeia seeds da planilha para formato de financas pessoais:
-- sem prefixo numerico no nome e sem CAIXA ALTA.
-- Os codigos continuam em pc_code/pc_group (usados nos relatorios).

-- ============================================================
-- 1. Categorias pai
-- ============================================================
UPDATE categories SET name = 'Receitas fixas'      WHERE id = 100 AND user_id IS NULL;
UPDATE categories SET name = 'Receitas variáveis'  WHERE id = 101 AND user_id IS NULL;
UPDATE categories SET name = 'Receitas extras'     WHERE id = 102 AND user_id IS NULL;
UPDATE categories SET name = 'Receitas extras 2'   WHERE id = 103 AND user_id IS NULL;
UPDATE categories SET name = 'Despesas fixas'      WHERE id = 200 AND user_id IS NULL;
UPDATE categories SET name = 'Despesas variáveis'  WHERE id = 201 AND user_id IS NULL;
UPDATE categories SET name = 'Despesas extras'     WHERE id = 202 AND user_id IS NULL;
UPDATE categories SET name = 'Investimentos planejados' WHERE id = 203 AND user_id IS NULL;
UPDATE categories SET name = 'Despesas diversas'   WHERE id = 204 AND user_id IS NULL;
UPDATE categories SET name = 'Despesas diversas 2' WHERE id = 205 AND user_id IS NULL;

-- ============================================================
-- 2. Subcategorias de receita
-- ============================================================
UPDATE categories SET name = 'Salário mensal'   WHERE user_id IS NULL AND parent_id = 100 AND name = 'SALARIO MENSAL';
UPDATE categories SET name = 'Adiantamento'     WHERE user_id IS NULL AND parent_id = 100 AND name = 'ADIANTAMENTO';
UPDATE categories SET name = 'Ajuda de custo'   WHERE user_id IS NULL AND parent_id = 100 AND name = 'AJUDA DE CUSTO';
UPDATE categories SET name = 'Férias'           WHERE user_id IS NULL AND parent_id = 100 AND name = 'FERIAS';
UPDATE categories SET name = '13º salário'      WHERE user_id IS NULL AND parent_id = 100 AND name = '13 SALARIO';
UPDATE categories SET name = 'Vale-refeição'    WHERE user_id IS NULL AND parent_id = 100 AND name = 'VALE REFEICAO';

UPDATE categories SET name = 'FGTS'             WHERE user_id IS NULL AND parent_id = 101 AND name = 'FGTS';
UPDATE categories SET name = 'Abono'            WHERE user_id IS NULL AND parent_id = 101 AND name = 'ABONO';
UPDATE categories SET name = 'Horas extras'     WHERE user_id IS NULL AND parent_id = 101 AND name = 'HORAS EXTRAS';
UPDATE categories SET name = 'Renda extra'      WHERE user_id IS NULL AND parent_id = 101 AND name = 'RENDA EXTRA';
UPDATE categories SET name = 'Outros'           WHERE user_id IS NULL AND parent_id = 101 AND name = 'OUTROS';
UPDATE categories SET name = 'Aplicações'       WHERE user_id IS NULL AND parent_id = 101 AND name = 'APLICACOES';

UPDATE categories SET name = 'Receita extra 1'  WHERE user_id IS NULL AND parent_id = 102 AND name = 'Receita Extra 1';
UPDATE categories SET name = 'Receita extra 2'  WHERE user_id IS NULL AND parent_id = 102 AND name = 'Receita Extra 2';
UPDATE categories SET name = 'Receita extra 3'  WHERE user_id IS NULL AND parent_id = 102 AND name = 'Receita Extra 3';
UPDATE categories SET name = 'Receita extra 4'  WHERE user_id IS NULL AND parent_id = 102 AND name = 'Receita Extra 4';
UPDATE categories SET name = 'Receita extra 5'  WHERE user_id IS NULL AND parent_id = 103 AND name = 'Receita Extra 5';

-- ============================================================
-- 3. Subcategorias de despesa
-- ============================================================
UPDATE categories SET name = 'Financiamento do apto' WHERE user_id IS NULL AND parent_id = 200 AND name = 'FINANCIAMENTO APTO';
UPDATE categories SET name = 'Condomínio'            WHERE user_id IS NULL AND parent_id = 200 AND name = 'CONDOMINIO';
UPDATE categories SET name = 'Luz'                   WHERE user_id IS NULL AND parent_id = 200 AND name = 'LUZ';
UPDATE categories SET name = 'Internet'              WHERE user_id IS NULL AND parent_id = 200 AND name = 'INTERNET';
UPDATE categories SET name = 'Telefone'              WHERE user_id IS NULL AND parent_id = 200 AND name = 'TELEFONIA MOVEL';
UPDATE categories SET name = 'Convênio'              WHERE user_id IS NULL AND parent_id = 200 AND name = 'CONVENIO';
UPDATE categories SET name = 'IPTU'                  WHERE user_id IS NULL AND parent_id = 200 AND name = 'IPTU';
UPDATE categories SET name = 'IPVA'                  WHERE user_id IS NULL AND parent_id = 200 AND name = 'IPVA';
UPDATE categories SET name = 'Casa'                  WHERE user_id IS NULL AND parent_id = 200 AND name = 'CASA';

UPDATE categories SET name = 'Cartões de crédito' WHERE user_id IS NULL AND parent_id = 201 AND name = 'CARTOES DE CREDITO';
UPDATE categories SET name = 'Empréstimos'        WHERE user_id IS NULL AND parent_id = 201 AND name = 'EMPRESTIMOS';
UPDATE categories SET name = 'Mercado'            WHERE user_id IS NULL AND parent_id = 201 AND name = 'MERCADO';
UPDATE categories SET name = 'Uber'               WHERE user_id IS NULL AND parent_id = 201 AND name = 'UBER';
UPDATE categories SET name = 'Outros'             WHERE user_id IS NULL AND parent_id = 201 AND name = 'OUTROS';

UPDATE categories SET name = 'Estúdio'              WHERE user_id IS NULL AND parent_id = 202 AND name = 'ESTUDIO';
UPDATE categories SET name = 'Infração de trânsito' WHERE user_id IS NULL AND parent_id = 202 AND name = 'INFRACAO TRANSITO';
UPDATE categories SET name = 'Faculdade'            WHERE user_id IS NULL AND parent_id = 202 AND name = 'FACULDADE';
UPDATE categories SET name = 'Cinema'               WHERE user_id IS NULL AND parent_id = 202 AND name = 'CINEMA';
UPDATE categories SET name = 'Restaurante'          WHERE user_id IS NULL AND parent_id = 202 AND name = 'RESTAURANTE';
UPDATE categories SET name = 'Roupas e calçados'    WHERE user_id IS NULL AND parent_id = 202 AND name = 'ROUPAS CALCADOS';
UPDATE categories SET name = 'Outros extras'        WHERE user_id IS NULL AND parent_id = 202 AND name = 'OUTROS EXTRAS';

UPDATE categories SET name = 'Ações'           WHERE user_id IS NULL AND parent_id = 203 AND name = 'ACOES';
UPDATE categories SET name = 'Tesouro Direto'  WHERE user_id IS NULL AND parent_id = 203 AND name = 'TESOURO DIRETO';
UPDATE categories SET name = 'Renda fixa'      WHERE user_id IS NULL AND parent_id = 203 AND name = 'RENDA FIXA';
UPDATE categories SET name = 'Poupança'        WHERE user_id IS NULL AND parent_id = 203 AND name = 'POUPANCA';

-- ============================================================
-- 4. Centros de custo -> grupos de gasto
-- ============================================================
UPDATE cost_centers SET name = 'Moradia'      WHERE id = 1  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Saúde'        WHERE id = 2  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Alimentação'  WHERE id = 3  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Transporte'   WHERE id = 4  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Lazer'        WHERE id = 5  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Reservas'     WHERE id = 6  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Dívida'       WHERE id = 7  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Estudos'      WHERE id = 8  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Trabalho'     WHERE id = 9  AND user_id IS NULL;
UPDATE cost_centers SET name = 'Outros'       WHERE id = 10 AND user_id IS NULL;

-- ============================================================
-- 5. Contatos padrao
-- ============================================================
UPDATE contacts SET name = 'Thais Araujo'    WHERE id = 1  AND user_id IS NULL;
UPDATE contacts SET name = 'Davison Campos'  WHERE id = 2  AND user_id IS NULL;
UPDATE contacts SET name = 'Elion Araujo'    WHERE id = 3  AND user_id IS NULL;
UPDATE contacts SET name = 'Vilma Prado'     WHERE id = 4  AND user_id IS NULL;
UPDATE contacts SET name = 'Estudio Lau'     WHERE id = 5  AND user_id IS NULL;
UPDATE contacts SET name = 'Casa Davison'    WHERE id = 6  AND user_id IS NULL;
UPDATE contacts SET name = 'Flex I'          WHERE id = 7  AND user_id IS NULL;
UPDATE contacts SET name = 'Cruzeiro do Sul' WHERE id = 8  AND user_id IS NULL;
UPDATE contacts SET name = 'Bancos'          WHERE id = 9  AND user_id IS NULL;
UPDATE contacts SET name = 'Casa Apto 63'    WHERE id = 10 AND user_id IS NULL;
UPDATE contacts SET name = 'Banda'           WHERE id = 11 AND user_id IS NULL;
