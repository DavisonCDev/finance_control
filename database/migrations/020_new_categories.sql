-- 020: Nova estrutura de categorias (categoria/subcategoria) + tipo de investimento 'fixed_income'.
-- Novas linhas recebem marcador pc_group='v2' para distinguir das antigas ate a limpeza final.

ALTER TABLE investments MODIFY COLUMN type
  ENUM('treasury','cdb','lci_lca','stock','etf','reit','crypto','fund','savings','pension','fixed_income','other') NOT NULL;

-- ============ RECEITAS (lista plana) ============
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Salário','income','work','#2E7D32',NULL,1,'v2'),
('Freelance','income','computer','#1976D2',NULL,2,'v2'),
('Comissão','income','percent','#00838F',NULL,3,'v2'),
('Rendimentos','income','trending_up','#7B1FA2',NULL,4,'v2'),
('Venda','income','sell','#5D4037',NULL,5,'v2'),
('Reembolso','income','replay','#00695C',NULL,6,'v2'),
('Benefícios','income','card_membership','#F9A825',NULL,7,'v2'),
('Outras receitas','income','add_circle','#388E3C',NULL,8,'v2');

-- ============ DESPESAS ============
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Moradia','expense','home','#D32F2F',NULL,1,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Aluguel','expense','home','#D32F2F',@p,1,'v2'),
('Financiamento','expense','apartment','#D32F2F',@p,2,'v2'),
('Condomínio','expense','apartment','#D32F2F',@p,3,'v2'),
('IPTU','expense','house','#D32F2F',@p,4,'v2'),
('Energia elétrica','expense','bolt','#D32F2F',@p,5,'v2'),
('Água','expense','water_drop','#D32F2F',@p,6,'v2'),
('Gás','expense','local_fire_department','#D32F2F',@p,7,'v2'),
('Internet','expense','wifi','#D32F2F',@p,8,'v2'),
('Telefone','expense','smartphone','#D32F2F',@p,9,'v2'),
('Manutenção e reparos','expense','build','#D32F2F',@p,10,'v2'),
('Móveis e decoração','expense','chair','#D32F2F',@p,11,'v2'),
('Serviços domésticos','expense','cleaning_services','#D32F2F',@p,12,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Alimentação','expense','restaurant','#F57C00',NULL,2,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Supermercado','expense','shopping_basket','#F57C00',@p,1,'v2'),
('Feira','expense','storefront','#F57C00',@p,2,'v2'),
('Padaria','expense','bakery_dining','#F57C00',@p,3,'v2'),
('Restaurantes','expense','restaurant','#F57C00',@p,4,'v2'),
('Delivery','expense','delivery_dining','#F57C00',@p,5,'v2'),
('Lanches','expense','fastfood','#F57C00',@p,6,'v2'),
('Café','expense','local_cafe','#F57C00',@p,7,'v2'),
('Bebidas','expense','local_bar','#F57C00',@p,8,'v2'),
('Alimentação no trabalho','expense','work','#F57C00',@p,9,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Transporte','expense','directions_car','#0288D1',NULL,3,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Combustível','expense','local_gas_station','#0288D1',@p,1,'v2'),
('Transporte público','expense','directions_bus','#0288D1',@p,2,'v2'),
('Uber/99','expense','local_taxi','#0288D1',@p,3,'v2'),
('Estacionamento','expense','local_parking','#0288D1',@p,4,'v2'),
('Pedágio','expense','toll','#0288D1',@p,5,'v2'),
('Manutenção','expense','build','#0288D1',@p,6,'v2'),
('Seguro','expense','shield','#0288D1',@p,7,'v2'),
('IPVA','expense','directions_car','#0288D1',@p,8,'v2'),
('Licenciamento','expense','description','#0288D1',@p,9,'v2'),
('Multas','expense','warning','#0288D1',@p,10,'v2'),
('Financiamento do veículo','expense','payments','#0288D1',@p,11,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Saúde','expense','local_hospital','#00796B',NULL,4,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Plano de saúde','expense','health_and_safety','#00796B',@p,1,'v2'),
('Consultas','expense','medical_services','#00796B',@p,2,'v2'),
('Exames','expense','biotech','#00796B',@p,3,'v2'),
('Medicamentos','expense','local_pharmacy','#00796B',@p,4,'v2'),
('Odontologia','expense','medical_services','#00796B',@p,5,'v2'),
('Terapias','expense','psychology','#00796B',@p,6,'v2'),
('Óculos e lentes','expense','visibility','#00796B',@p,7,'v2'),
('Academia','expense','fitness_center','#00796B',@p,8,'v2'),
('Outros cuidados de saúde','expense','favorite','#00796B',@p,9,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Compras','expense','shopping_cart','#E64A19',NULL,5,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Roupas','expense','checkroom','#E64A19',@p,1,'v2'),
('Calçados','expense','shopping_bag','#E64A19',@p,2,'v2'),
('Eletrônicos','expense','devices','#E64A19',@p,3,'v2'),
('Celular','expense','smartphone','#E64A19',@p,4,'v2'),
('Computador','expense','computer','#E64A19',@p,5,'v2'),
('Casa','expense','chair','#E64A19',@p,6,'v2'),
('Presentes','expense','card_giftcard','#E64A19',@p,7,'v2'),
('Compras online','expense','shopping_bag','#E64A19',@p,8,'v2'),
('Outros','expense','more_horiz','#E64A19',@p,9,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Lazer e entretenimento','expense','sports_esports','#C2185B',NULL,6,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Cinema','expense','movie','#C2185B',@p,1,'v2'),
('Shows','expense','music_note','#C2185B',@p,2,'v2'),
('Eventos','expense','event','#C2185B',@p,3,'v2'),
('Viagens','expense','flight','#C2185B',@p,4,'v2'),
('Passeios','expense','park','#C2185B',@p,5,'v2'),
('Jogos','expense','sports_esports','#C2185B',@p,6,'v2'),
('Streaming','expense','live_tv','#C2185B',@p,7,'v2'),
('Música','expense','headphones','#C2185B',@p,8,'v2'),
('Livros','expense','menu_book','#C2185B',@p,9,'v2'),
('Hobbies','expense','palette','#C2185B',@p,10,'v2'),
('Esportes','expense','sports_soccer','#C2185B',@p,11,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Assinaturas e serviços digitais','expense','subscriptions','#5E35B1',NULL,7,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Netflix','expense','live_tv','#5E35B1',@p,1,'v2'),
('Spotify','expense','music_note','#5E35B1',@p,2,'v2'),
('YouTube','expense','play_circle','#5E35B1',@p,3,'v2'),
('Amazon Prime','expense','inventory_2','#5E35B1',@p,4,'v2'),
('Disney+','expense','movie','#5E35B1',@p,5,'v2'),
('Game Pass','expense','sports_esports','#5E35B1',@p,6,'v2'),
('Armazenamento em nuvem','expense','cloud','#5E35B1',@p,7,'v2'),
('Aplicativos','expense','apps','#5E35B1',@p,8,'v2'),
('Softwares','expense','code','#5E35B1',@p,9,'v2'),
('Inteligência artificial','expense','smart_toy','#5E35B1',@p,10,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Cuidados pessoais','expense','spa','#AD1457',NULL,8,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Cabeleireiro','expense','content_cut','#AD1457',@p,1,'v2'),
('Barbearia','expense','content_cut','#AD1457',@p,2,'v2'),
('Cosméticos','expense','face','#AD1457',@p,3,'v2'),
('Higiene pessoal','expense','soap','#AD1457',@p,4,'v2'),
('Estética','expense','face_retouching_natural','#AD1457',@p,5,'v2'),
('Academia','expense','fitness_center','#AD1457',@p,6,'v2'),
('Roupas','expense','checkroom','#AD1457',@p,7,'v2'),
('Outros','expense','more_horiz','#AD1457',@p,8,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Educação','expense','school','#512DA8',NULL,9,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Faculdade','expense','school','#512DA8',@p,1,'v2'),
('Cursos','expense','menu_book','#512DA8',@p,2,'v2'),
('Certificações','expense','workspace_premium','#512DA8',@p,3,'v2'),
('Livros','expense','menu_book','#512DA8',@p,4,'v2'),
('Material escolar','expense','backpack','#512DA8',@p,5,'v2'),
('Mensalidades','expense','payments','#512DA8',@p,6,'v2'),
('Cursos online','expense','computer','#512DA8',@p,7,'v2'),
('Idiomas','expense','translate','#512DA8',@p,8,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Pets','expense','pets','#795548',NULL,10,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Ração','expense','pets','#795548',@p,1,'v2'),
('Veterinário','expense','medical_services','#795548',@p,2,'v2'),
('Medicamentos','expense','medication','#795548',@p,3,'v2'),
('Banho e tosa','expense','bathtub','#795548',@p,4,'v2'),
('Acessórios','expense','toys','#795548',@p,5,'v2'),
('Pet shop','expense','store','#795548',@p,6,'v2'),
('Plano veterinário','expense','health_and_safety','#795548',@p,7,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Família','expense','family_restroom','#00897B',NULL,11,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Filhos','expense','child_care','#00897B',@p,1,'v2'),
('Escola','expense','school','#00897B',@p,2,'v2'),
('Pensão','expense','payments','#00897B',@p,3,'v2'),
('Cuidados com familiares','expense','elderly','#00897B',@p,4,'v2'),
('Mesada','expense','payments','#00897B',@p,5,'v2'),
('Presentes','expense','card_giftcard','#00897B',@p,6,'v2'),
('Despesas compartilhadas','expense','groups','#00897B',@p,7,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Financeiro','expense','account_balance','#455A64',NULL,12,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Taxas bancárias','expense','account_balance','#455A64',@p,1,'v2'),
('Tarifas','expense','receipt','#455A64',@p,2,'v2'),
('Juros','expense','percent','#455A64',@p,3,'v2'),
('Anuidade de cartão','expense','credit_card','#455A64',@p,4,'v2'),
('IOF','expense','percent','#455A64',@p,5,'v2'),
('Empréstimos','expense','money_off','#455A64',@p,6,'v2'),
('Financiamentos','expense','payments','#455A64',@p,7,'v2'),
('Renegociação de dívidas','expense','handshake','#455A64',@p,8,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Impostos e obrigações','expense','gavel','#BF360C',NULL,13,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Imposto de renda','expense','description','#BF360C',@p,1,'v2'),
('IPTU','expense','house','#BF360C',@p,2,'v2'),
('IPVA','expense','directions_car','#BF360C',@p,3,'v2'),
('Taxas públicas','expense','account_balance','#BF360C',@p,4,'v2'),
('Documentação','expense','description','#BF360C',@p,5,'v2'),
('Multas','expense','warning','#BF360C',@p,6,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Doações e presentes','expense','card_giftcard','#6D4C41',NULL,14,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Presentes','expense','card_giftcard','#6D4C41',@p,1,'v2'),
('Doações','expense','volunteer_activism','#6D4C41',@p,2,'v2'),
('Ajuda familiar','expense','family_restroom','#6D4C41',@p,3,'v2'),
('Contribuições','expense','groups','#6D4C41',@p,4,'v2');

INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES ('Outras despesas','expense','more_horiz','#607D8B',NULL,15,'v2');
SET @p = LAST_INSERT_ID();
INSERT INTO categories (name, type, icon, color, parent_id, sort_order, pc_group) VALUES
('Despesas diversas','expense','more_horiz','#607D8B',@p,1,'v2'),
('Despesas emergenciais','expense','warning','#607D8B',@p,2,'v2'),
('Não categorizado','expense','help','#607D8B',@p,3,'v2');

-- ============ REMAPEAMENTO ============
-- Mapa nome-antigo -> (novo nome, novo pai). Nomes ambiguos usam o pai para desempatar.
DROP TEMPORARY TABLE IF EXISTS _catmap;
CREATE TEMPORARY TABLE _catmap (old_name VARCHAR(60), old_type VARCHAR(10) NULL, new_name VARCHAR(60), new_parent VARCHAR(60) NULL) COLLATE utf8mb4_unicode_ci;
INSERT INTO _catmap VALUES
-- receitas
('Salário',NULL,'Salário',NULL),
('Salário mensal',NULL,'Salário',NULL),
('Adiantamento',NULL,'Salário',NULL),
('Férias',NULL,'Salário',NULL),
('13º salário',NULL,'Salário',NULL),
('Horas extras',NULL,'Salário',NULL),
('Freelance',NULL,'Freelance',NULL),
('Renda extra',NULL,'Freelance',NULL),
('Comissão',NULL,'Comissão',NULL),
('Venda',NULL,'Venda',NULL),
('Investimentos',NULL,'Rendimentos',NULL),
('Aplicações',NULL,'Rendimentos',NULL),
('Ajuda de custo',NULL,'Benefícios',NULL),
('Vale-refeição',NULL,'Benefícios',NULL),
('FGTS',NULL,'Benefícios',NULL),
('Abono',NULL,'Benefícios',NULL),
('Outras receitas',NULL,'Outras receitas',NULL),
('Outros','income','Outras receitas',NULL),
('Aluguel recebido',NULL,'Outras receitas',NULL),
('Receitas fixas',NULL,'Salário',NULL),
('Receitas variáveis',NULL,'Outras receitas',NULL),
('Receitas extras',NULL,'Outras receitas',NULL),
-- despesas: pais
('Moradia',NULL,'Moradia',NULL),
('Alimentação',NULL,'Alimentação',NULL),
('Transporte',NULL,'Transporte',NULL),
('Lazer',NULL,'Lazer e entretenimento',NULL),
('Saúde',NULL,'Saúde',NULL),
('Educação',NULL,'Educação',NULL),
('Contas',NULL,'Moradia',NULL),
('Compras',NULL,'Compras',NULL),
('Outras despesas',NULL,'Outras despesas',NULL),
('Despesas fixas',NULL,'Despesas diversas','Outras despesas'),
('Despesas variáveis',NULL,'Despesas diversas','Outras despesas'),
('Despesas extras',NULL,'Despesas diversas','Outras despesas'),
('Investimentos planejados',NULL,'Despesas diversas','Outras despesas'),
('Despesas diversas',NULL,'Despesas diversas','Outras despesas'),
-- despesas: subs
('Aluguel',NULL,'Aluguel','Moradia'),
('Condomínio',NULL,'Condomínio','Moradia'),
('Manutenção',NULL,'Manutenção e reparos','Moradia'),
('Energia',NULL,'Energia elétrica','Moradia'),
('Luz',NULL,'Energia elétrica','Moradia'),
('Água',NULL,'Água','Moradia'),
('Internet',NULL,'Internet','Moradia'),
('Telefone',NULL,'Telefone','Moradia'),
('IPTU',NULL,'IPTU','Moradia'),
('Financiamento do apto',NULL,'Financiamento','Moradia'),
('Supermercado',NULL,'Supermercado','Alimentação'),
('Mercado',NULL,'Supermercado','Alimentação'),
('Restaurante',NULL,'Restaurantes','Alimentação'),
('Delivery',NULL,'Delivery','Alimentação'),
('Combustível',NULL,'Combustível','Transporte'),
('Transporte público',NULL,'Transporte público','Transporte'),
('Aplicativos',NULL,'Uber/99','Transporte'),
('Uber',NULL,'Uber/99','Transporte'),
('Estacionamento',NULL,'Estacionamento','Transporte'),
('IPVA',NULL,'IPVA','Transporte'),
('Infração de trânsito',NULL,'Multas','Transporte'),
('Plano de saúde',NULL,'Plano de saúde','Saúde'),
('Convênio',NULL,'Plano de saúde','Saúde'),
('Consultas',NULL,'Consultas','Saúde'),
('Farmácia',NULL,'Medicamentos','Saúde'),
('Streaming',NULL,'Streaming','Lazer e entretenimento'),
('Viagens',NULL,'Viagens','Lazer e entretenimento'),
('Cinema',NULL,'Cinema','Lazer e entretenimento'),
('Estúdio',NULL,'Hobbies','Lazer e entretenimento'),
('Casa',NULL,'Casa','Compras'),
('Roupas e calçados',NULL,'Roupas','Compras'),
('Assinaturas',NULL,'Assinaturas e serviços digitais',NULL),
('Faculdade',NULL,'Faculdade','Educação'),
('Cartões de crédito',NULL,'Anuidade de cartão','Financeiro'),
('Empréstimos',NULL,'Empréstimos','Financeiro'),
('Dívidas',NULL,'Renegociação de dívidas','Financeiro'),
('Outros','expense','Despesas diversas','Outras despesas'),
('Outros extras',NULL,'Despesas diversas','Outras despesas'),
('Ações',NULL,'Despesas diversas','Outras despesas'),
('Tesouro Direto',NULL,'Despesas diversas','Outras despesas'),
('Renda fixa',NULL,'Despesas diversas','Outras despesas'),
('Poupança',NULL,'Despesas diversas','Outras despesas');

-- Remapeia referencias pelo mapa de nomes.
UPDATE transactions t
JOIN categories oc ON oc.id = t.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN _catmap m ON m.old_name = oc.name AND (m.old_type IS NULL OR oc.type = m.old_type)
JOIN categories nc ON nc.name = m.new_name AND nc.pc_group = 'v2'
LEFT JOIN categories ncp ON ncp.id = nc.parent_id
SET t.category_id = nc.id
WHERE (m.new_parent IS NULL AND nc.parent_id IS NULL) OR ncp.name = m.new_parent;

UPDATE budgets b
JOIN categories oc ON oc.id = b.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN _catmap m ON m.old_name = oc.name AND (m.old_type IS NULL OR oc.type = m.old_type)
JOIN categories nc ON nc.name = m.new_name AND nc.pc_group = 'v2'
LEFT JOIN categories ncp ON ncp.id = nc.parent_id
SET b.category_id = nc.id
WHERE (m.new_parent IS NULL AND nc.parent_id IS NULL) OR ncp.name = m.new_parent;

UPDATE recurring_transactions r
JOIN categories oc ON oc.id = r.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN _catmap m ON m.old_name = oc.name AND (m.old_type IS NULL OR oc.type = m.old_type)
JOIN categories nc ON nc.name = m.new_name AND nc.pc_group = 'v2'
LEFT JOIN categories ncp ON ncp.id = nc.parent_id
SET r.category_id = nc.id
WHERE (m.new_parent IS NULL AND nc.parent_id IS NULL) OR ncp.name = m.new_parent;

UPDATE installments i
JOIN categories oc ON oc.id = i.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN _catmap m ON m.old_name = oc.name AND (m.old_type IS NULL OR oc.type = m.old_type)
JOIN categories nc ON nc.name = m.new_name AND nc.pc_group = 'v2'
LEFT JOIN categories ncp ON ncp.id = nc.parent_id
SET i.category_id = nc.id
WHERE (m.new_parent IS NULL AND nc.parent_id IS NULL) OR ncp.name = m.new_parent;

-- Fallback: o que sobrou apontando para categoria antiga vai para o generico do mesmo tipo.
UPDATE transactions t
JOIN categories oc ON oc.id = t.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN categories nc ON nc.pc_group = 'v2' AND nc.name = IF(oc.type='income','Outras receitas','Não categorizado')
SET t.category_id = nc.id;

UPDATE budgets b
JOIN categories oc ON oc.id = b.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN categories nc ON nc.pc_group = 'v2' AND nc.name = IF(oc.type='income','Outras receitas','Não categorizado')
SET b.category_id = nc.id;

UPDATE recurring_transactions r
JOIN categories oc ON oc.id = r.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN categories nc ON nc.pc_group = 'v2' AND nc.name = IF(oc.type='income','Outras receitas','Não categorizado')
SET r.category_id = nc.id;

UPDATE installments i
JOIN categories oc ON oc.id = i.category_id AND (oc.pc_group IS NULL OR oc.pc_group <> 'v2')
JOIN categories nc ON nc.pc_group = 'v2' AND nc.name = 'Não categorizado'
SET i.category_id = nc.id;

-- Refino por descricao (categoria mais indicada para dados existentes).
UPDATE transactions t
JOIN categories nc ON nc.pc_group='v2' AND nc.name='Computador'
JOIN categories p ON p.id=nc.parent_id AND p.name='Compras'
SET t.category_id=nc.id WHERE t.description LIKE 'Notebook%';

UPDATE transactions t
JOIN categories nc ON nc.pc_group='v2' AND nc.name='Compras online'
JOIN categories p ON p.id=nc.parent_id AND p.name='Compras'
SET t.category_id=nc.id WHERE t.description LIKE 'Mercado Livre%';

UPDATE transactions t
JOIN categories nc ON nc.pc_group='v2' AND nc.name='Feira'
JOIN categories p ON p.id=nc.parent_id AND p.name='Alimentação'
SET t.category_id=nc.id WHERE t.description LIKE '%Feira%';

UPDATE transactions t
JOIN categories nc ON nc.pc_group='v2' AND nc.name='Empréstimos'
JOIN categories p ON p.id=nc.parent_id AND p.name='Financeiro'
SET t.category_id=nc.id WHERE t.description LIKE 'Empréstimo%';

-- Remove categorias antigas (FKs restantes caem para NULL via ON DELETE SET NULL).
DELETE FROM categories WHERE pc_group IS NULL OR pc_group <> 'v2';
UPDATE categories SET pc_group = NULL WHERE pc_group = 'v2';
DROP TEMPORARY TABLE IF EXISTS _catmap;
