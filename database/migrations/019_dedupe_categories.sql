-- Remove categorias duplicadas e itens com numeral vindos da planilha.
-- Condominio, Restaurante, Internet e Telefone ja existem nas arvores
-- de Moradia/Alimentacao/Contas; as copias nos grupos da planilha sao removidas
-- e eventuais referencias sao repontadas para a versao original.

UPDATE transactions SET category_id = 18 WHERE category_id = 224;
UPDATE budgets SET category_id = 18 WHERE category_id = 224;
UPDATE recurring_transactions SET category_id = 18 WHERE category_id = 224;
DELETE FROM categories WHERE id = 224;

UPDATE transactions SET category_id = 21 WHERE category_id = 241;
UPDATE budgets SET category_id = 21 WHERE category_id = 241;
UPDATE recurring_transactions SET category_id = 21 WHERE category_id = 241;
DELETE FROM categories WHERE id = 241;

UPDATE transactions SET category_id = 34 WHERE category_id = 226;
UPDATE budgets SET category_id = 34 WHERE category_id = 226;
UPDATE recurring_transactions SET category_id = 34 WHERE category_id = 226;
DELETE FROM categories WHERE id = 226;

UPDATE transactions SET category_id = 35 WHERE category_id = 227;
UPDATE budgets SET category_id = 35 WHERE category_id = 227;
UPDATE recurring_transactions SET category_id = 35 WHERE category_id = 227;
DELETE FROM categories WHERE id = 227;

-- "Despesas diversas 2" e "Despesas diversas": mesma coisa.
UPDATE transactions SET category_id = 204 WHERE category_id = 205;
UPDATE budgets SET category_id = 204 WHERE category_id = 205;
UPDATE recurring_transactions SET category_id = 204 WHERE category_id = 205;
DELETE FROM categories WHERE id = 205;

-- "Receitas extras 2" e as filhas genericas "Receita extra 1..5":
-- tudo vira "Receitas extras" (id 102).
UPDATE transactions SET category_id = 102 WHERE category_id IN (103, 218, 219, 220, 221, 222);
UPDATE budgets SET category_id = 102 WHERE category_id IN (103, 218, 219, 220, 221, 222);
UPDATE recurring_transactions SET category_id = 102 WHERE category_id IN (103, 218, 219, 220, 221, 222);
DELETE FROM categories WHERE parent_id = 103;
DELETE FROM categories WHERE id = 103;
DELETE FROM categories WHERE id IN (218, 219, 220, 221);
