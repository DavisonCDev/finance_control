-- Seed Plano de Contas, Centros de Custos, Bancos, Contatos
-- Baseado na planilha CONTROLE FINANCEIRO_2026_R1
-- Idempotente: usa INSERT IGNORE / ON DUPLICATE KEY UPDATE

-- ============================================================
-- 1. CATEGORIES: Niveis superiores (pais) do PC
--    Receitas Fixas, Receitas Variaveis, Despesas Fixas,
--    Despesas Variaveis, Despesas Extras, Investimento
-- ============================================================

-- === RECEITAS (income) ===
INSERT INTO categories (id, user_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (100, NULL, 'Receitas fixas',     'income', '#2E7D32', 'attach_money', TRUE, 10, '1.1',   NULL),
  (101, NULL, 'Receitas variáveis', 'income', '#388E3C', 'trending_up',  TRUE, 11, '1.2',   NULL),
  (102, NULL, 'Receitas extras',    'income', '#43A047', 'add_circle',   TRUE, 12, '1.3',   NULL),
  (103, NULL, 'Receitas extras 2',  'income', '#66BB6A', 'savings',      TRUE, 13, '1.4',   NULL)
ON DUPLICATE KEY UPDATE name = VALUES(name), pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- === DESPESAS (expense) ===
INSERT INTO categories (id, user_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (200, NULL, 'Despesas fixas',     'expense', '#C62828', 'payments',         TRUE, 20, '2.1', NULL),
  (201, NULL, 'Despesas variáveis', 'expense', '#D32F2F', 'local_grocery_store', TRUE, 21, '2.2', NULL),
  (202, NULL, 'Despesas extras',    'expense', '#E53935', 'card_giftcard',    TRUE, 22, '2.3', NULL),
  (203, NULL, 'Investimentos planejados', 'expense', '#6A1B9A', 'trending_up', TRUE, 23, '2.4', 'Investimento'),
  (204, NULL, 'Despesas diversas',  'expense', '#7B1FA2', 'more_horiz',       TRUE, 24, '2.5', NULL),
  (205, NULL, 'Despesas diversas 2','expense', '#8E24AA', 'list_alt',         TRUE, 25, '2.6', NULL)
ON DUPLICATE KEY UPDATE name = VALUES(name), pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- ============================================================
-- 2. SUBCATEGORIES RECEITAS (filhos) - PC_Rec da planilha
--    pc_group: Receita1..4, Custo1..3
-- ============================================================

-- 1.1 RECEITAS FIXAS (pai 100) - Receita1
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 100, 'Salário mensal',   'income', '#2E7D32', 'work',        TRUE, 1, '1.1.1', 'Receita1'),
  (NULL, 100, 'Adiantamento',     'income', '#2E7D32', 'schedule',    TRUE, 2, '1.1.2', 'Receita1'),
  (NULL, 100, 'Ajuda de custo',   'income', '#2E7D32', 'luggage',     TRUE, 3, '1.1.3', 'Receita1'),
  (NULL, 100, 'Férias',           'income', '#2E7D32', 'beach_access',TRUE, 4, '1.1.4', 'Receita1'),
  (NULL, 100, '13º salário',      'income', '#2E7D32', 'celebration', TRUE, 5, '1.1.5', 'Receita1'),
  (NULL, 100, 'Vale-refeição',    'income', '#2E7D32', 'restaurant',  TRUE, 6, '1.1.6', 'Receita1')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- 1.2 RECEITAS VARIAVEIS (pai 101) - Receita2
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 101, 'FGTS',               'income', '#388E3C', 'account_balance',TRUE, 1, '1.2.1', 'Receita2'),
  (NULL, 101, 'Abono',              'income', '#388E3C', 'card_membership',TRUE, 2, '1.2.2', 'Receita2'),
  (NULL, 101, 'Horas extras',       'income', '#388E3C', 'access_time',    TRUE, 3, '1.2.3', 'Receita2'),
  (NULL, 101, 'Renda extra',        'income', '#388E3C', 'monetization_on',TRUE, 4, '1.2.4', 'Receita2'),
  (NULL, 101, 'Outros',             'income', '#388E3C', 'add_circle',     TRUE, 5, '1.2.5', 'Receita2'),
  (NULL, 101, 'Aplicações',         'income', '#388E3C', 'savings',        TRUE, 6, '1.2.6', 'Receita2')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- 1.3 OUTRAS RECEITAS 1 (pai 102) - Receita3
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 102, 'Receita extra 1', 'income', '#43A047', 'point_of_sale', TRUE, 1, '1.3.1', 'Receita3'),
  (NULL, 102, 'Receita extra 2', 'income', '#43A047', 'point_of_sale', TRUE, 2, '1.3.2', 'Receita3'),
  (NULL, 102, 'Receita extra 3', 'income', '#43A047', 'point_of_sale', TRUE, 3, '1.3.3', 'Receita3'),
  (NULL, 102, 'Receita extra 4', 'income', '#43A047', 'point_of_sale', TRUE, 4, '1.3.4', 'Receita3')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- 1.4 OUTRAS RECEITAS 2 (pai 103) - Receita4
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 103, 'Receita extra 5', 'income', '#66BB6A', 'payments', TRUE, 1, '1.4.1', 'Receita4')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- ============================================================
-- 3. SUBCATEGORIES DESPESAS FIXAS (2.1 pai 200) - Despesa1
-- ============================================================
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 200, 'Financiamento do apto','expense','#C62828','apartment',      TRUE, 1, '2.1.1','Despesa1'),
  (NULL, 200, 'Condomínio',           'expense','#C62828','home_work',      TRUE, 2, '2.1.2','Despesa1'),
  (NULL, 200, 'Luz',                  'expense','#C62828','bolt',           TRUE, 3, '2.1.3','Despesa1'),
  (NULL, 200, 'Internet',             'expense','#C62828','wifi',           TRUE, 4, '2.1.4','Despesa1'),
  (NULL, 200, 'Telefone',             'expense','#C62828','smartphone',     TRUE, 5, '2.1.5','Despesa1'),
  (NULL, 200, 'Convênio',             'expense','#C62828','health_and_safety', TRUE, 6,'2.1.6','Despesa1'),
  (NULL, 200, 'IPTU',                 'expense','#C62828','house',          TRUE, 7, '2.1.7','Despesa1'),
  (NULL, 200, 'IPVA',                 'expense','#C62828','directions_car', TRUE, 8, '2.1.8','Despesa1'),
  (NULL, 200, 'Casa',                 'expense','#C62828','home',           TRUE, 9, '2.1.9','Despesa1')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- ============================================================
-- 4. SUBCATEGORIES DESPESAS VARIAVEIS (2.2 pai 201) - Custo1..Custo3, Despesa2
-- ============================================================
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 201, 'Cartões de crédito', 'expense','#D32F2F','credit_card',    TRUE, 1, '2.2.1','Custo1'),
  (NULL, 201, 'Empréstimos',        'expense','#D32F2F','money_off',      TRUE, 2, '2.2.2','Custo1'),
  (NULL, 201, 'Mercado',            'expense','#D32F2F','local_grocery_store', TRUE, 3, '2.2.3','Custo2'),
  (NULL, 201, 'Uber',               'expense','#D32F2F','local_taxi',     TRUE, 4, '2.2.4','Custo3'),
  (NULL, 201, 'Outros',             'expense','#D32F2F','more_horiz',     TRUE, 5, '2.2.5','Despesa2')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- ============================================================
-- 5. SUBCATEGORIES DESPESAS EXTRAS (2.3 pai 202) - Despesa3..Despesa5, Imposto
-- ============================================================
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 202, 'Estúdio',             'expense','#E53935','music_video',    TRUE, 1, '2.3.1','Despesa3'),
  (NULL, 202, 'Infração de trânsito','expense','#E53935','warning',        TRUE, 2, '2.3.2','Despesa3'),
  (NULL, 202, 'Faculdade',           'expense','#E53935','school',         TRUE, 3, '2.3.3','Despesa4'),
  (NULL, 202, 'Cinema',              'expense','#E53935','movie',          TRUE, 4, '2.3.4','Despesa4'),
  (NULL, 202, 'Restaurante',         'expense','#E53935','restaurant',     TRUE, 5, '2.3.5','Despesa4'),
  (NULL, 202, 'Roupas e calçados',   'expense','#E53935','checkroom',      TRUE, 6, '2.3.6','Despesa5'),
  (NULL, 202, 'Outros extras',       'expense','#E53935','add_circle',     TRUE, 7, '2.3.7','Imposto')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- ============================================================
-- 6. SUBCATEGORIES INVESTIMENTO (2.4 pai 203) - Investimento
-- ============================================================
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order, pc_code, pc_group) VALUES
  (NULL, 203, 'Ações',               'expense','#6A1B9A','show_chart',     TRUE, 1, '2.4.1','Investimento'),
  (NULL, 203, 'Tesouro Direto',      'expense','#6A1B9A','account_balance_wallet',TRUE,2,'2.4.2','Investimento'),
  (NULL, 203, 'Renda fixa',          'expense','#6A1B9A','savings',        TRUE, 3, '2.4.3','Investimento'),
  (NULL, 203, 'Poupança',            'expense','#6A1B9A','piggy_bank',     TRUE, 4, '2.4.4','Investimento')
ON DUPLICATE KEY UPDATE pc_code = VALUES(pc_code), pc_group = VALUES(pc_group), is_system = TRUE;

-- ============================================================
-- 7. CENTROS DE CUSTO (PC_CC) - 10 padrao
--    user_id NULL = padrao do sistema (igual categories)
-- ============================================================
ALTER TABLE cost_centers MODIFY user_id INT NULL;
ALTER TABLE contacts MODIFY user_id INT NULL;

INSERT INTO cost_centers (id, user_id, name, active, sort_order, code) VALUES
  (1, NULL, 'Moradia',      TRUE, 1,  '3.1.1'),
  (2, NULL, 'Saúde',        TRUE, 2,  '3.1.2'),
  (3, NULL, 'Alimentação',  TRUE, 3,  '3.1.3'),
  (4, NULL, 'Transporte',   TRUE, 4,  '3.1.4'),
  (5, NULL, 'Lazer',        TRUE, 5,  '3.1.5'),
  (6, NULL, 'Reservas',     TRUE, 6,  '3.1.6'),
  (7, NULL, 'Dívida',       TRUE, 7,  '3.1.7'),
  (8, NULL, 'Estudos',      TRUE, 8,  '3.1.8'),
  (9, NULL, 'Trabalho',     TRUE, 9,  '3.1.9'),
  (10,NULL, 'Outros',       TRUE, 10, '3.1.10')
ON DUPLICATE KEY UPDATE name = VALUES(name), code = VALUES(code), sort_order = VALUES(sort_order);

-- ============================================================
-- 8. ACCOUNTS / BANCOS (PC_Banco)
--    Contas sao por usuario (saldo e individual). Nao ha seed
--    global: cada usuario cadastra seus bancos.
-- ============================================================

-- ============================================================
-- 9. CONTACTS / CLIENTES E FORNECEDORES (PC_Cli) - 11 padrao
-- ============================================================
INSERT INTO contacts (id, user_id, name, type, phone, email, notes, active) VALUES
  (1,  NULL, 'Thais Araujo',      'customer', NULL, NULL, NULL, TRUE),
  (2,  NULL, 'Davison Campos',    'customer', NULL, NULL, NULL, TRUE),
  (3,  NULL, 'Elion Araujo',      'customer', NULL, NULL, NULL, TRUE),
  (4,  NULL, 'Vilma Prado',       'customer', NULL, NULL, NULL, TRUE),
  (5,  NULL, 'Estudio Lau',       'supplier', NULL, NULL, NULL, TRUE),
  (6,  NULL, 'Casa Davison',      'other',    NULL, NULL, NULL, TRUE),
  (7,  NULL, 'Flex I',            'supplier', NULL, NULL, NULL, TRUE),
  (8,  NULL, 'Cruzeiro do Sul',   'supplier', NULL, NULL, NULL, TRUE),
  (9,  NULL, 'Bancos',            'other',    NULL, NULL, NULL, TRUE),
  (10, NULL, 'Casa Apto 63',      'other',    NULL, NULL, NULL, TRUE),
  (11, NULL, 'Banda',             'customer', NULL, NULL, NULL, TRUE)
ON DUPLICATE KEY UPDATE name = VALUES(name), type = VALUES(type);
