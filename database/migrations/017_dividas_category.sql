-- Nova categoria "Dividas" (subcategoria de Despesas fixas).
-- Idempotente: so insere se ainda nao existir.
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group)
SELECT NULL, 200, 'Dívidas', 'expense', '#8E24AA', 'account_balance_wallet', TRUE, 99, '2.1.10', 'Despesa1'
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1 FROM categories c WHERE c.name = 'Dívidas' AND c.user_id IS NULL
);
