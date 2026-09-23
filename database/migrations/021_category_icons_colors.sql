-- 021: icone e cor individuais para cada categoria/subcategoria.
-- Paleta baseada em cores Material; subcategorias mantem a familia de cor do
-- pai, mas com tonalidade propria, para leitura facil em temas Material You.

-- ============ RECEITAS ============
UPDATE categories SET icon='work', color='#2E7D32' WHERE name='Salário' AND type='income';
UPDATE categories SET icon='laptop', color='#1976D2' WHERE name='Freelance' AND type='income';
UPDATE categories SET icon='percent', color='#00838F' WHERE name='Comissão' AND type='income';
UPDATE categories SET icon='trending_up', color='#7B1FA2' WHERE name='Rendimentos' AND type='income';
UPDATE categories SET icon='sell', color='#5D4037' WHERE name='Venda' AND type='income';
UPDATE categories SET icon='replay', color='#00695C' WHERE name='Reembolso' AND type='income';
UPDATE categories SET icon='card_giftcard', color='#F9A825' WHERE name='Benefícios' AND type='income';
UPDATE categories SET icon='add_circle', color='#388E3C' WHERE name='Outras receitas' AND type='income';

-- ============ MORADIA ============
UPDATE categories SET icon='home', color='#D32F2F' WHERE name='Moradia' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Moradia' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Aluguel' THEN 'key'
  WHEN 'Financiamento' THEN 'apartment'
  WHEN 'Condomínio' THEN 'domain'
  WHEN 'IPTU' THEN 'house'
  WHEN 'Energia elétrica' THEN 'bolt'
  WHEN 'Água' THEN 'water_drop'
  WHEN 'Gás' THEN 'local_fire_department'
  WHEN 'Internet' THEN 'wifi'
  WHEN 'Telefone' THEN 'call'
  WHEN 'Manutenção e reparos' THEN 'build'
  WHEN 'Móveis e decoração' THEN 'chair'
  WHEN 'Serviços domésticos' THEN 'cleaning_services'
END,
c.color = CASE c.name
  WHEN 'Aluguel' THEN '#C62828'
  WHEN 'Financiamento' THEN '#5D4037'
  WHEN 'Condomínio' THEN '#4527A0'
  WHEN 'IPTU' THEN '#AD1457'
  WHEN 'Energia elétrica' THEN '#F9A825'
  WHEN 'Água' THEN '#0277BD'
  WHEN 'Gás' THEN '#EF6C00'
  WHEN 'Internet' THEN '#00838F'
  WHEN 'Telefone' THEN '#558B2F'
  WHEN 'Manutenção e reparos' THEN '#6D4C41'
  WHEN 'Móveis e decoração' THEN '#7B1FA2'
  WHEN 'Serviços domésticos' THEN '#546E7A'
END;

-- ============ ALIMENTAÇÃO ============
UPDATE categories SET icon='restaurant', color='#F57C00' WHERE name='Alimentação' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Alimentação' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Supermercado' THEN 'shopping_basket'
  WHEN 'Feira' THEN 'storefront'
  WHEN 'Padaria' THEN 'bakery_dining'
  WHEN 'Restaurantes' THEN 'restaurant'
  WHEN 'Delivery' THEN 'delivery_dining'
  WHEN 'Lanches' THEN 'fastfood'
  WHEN 'Café' THEN 'local_cafe'
  WHEN 'Bebidas' THEN 'local_bar'
  WHEN 'Alimentação no trabalho' THEN 'lunch_dining'
END,
c.color = CASE c.name
  WHEN 'Supermercado' THEN '#EF6C00'
  WHEN 'Feira' THEN '#558B2F'
  WHEN 'Padaria' THEN '#8D6E63'
  WHEN 'Restaurantes' THEN '#D84315'
  WHEN 'Delivery' THEN '#C62828'
  WHEN 'Lanches' THEN '#FBC02D'
  WHEN 'Café' THEN '#6D4C41'
  WHEN 'Bebidas' THEN '#7B1FA2'
  WHEN 'Alimentação no trabalho' THEN '#00838F'
END;

-- ============ TRANSPORTE ============
UPDATE categories SET icon='directions_car', color='#0288D1' WHERE name='Transporte' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Transporte' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Combustível' THEN 'local_gas_station'
  WHEN 'Transporte público' THEN 'directions_bus'
  WHEN 'Uber/99' THEN 'local_taxi'
  WHEN 'Estacionamento' THEN 'local_parking'
  WHEN 'Pedágio' THEN 'toll'
  WHEN 'Manutenção' THEN 'car_repair'
  WHEN 'Seguro' THEN 'shield'
  WHEN 'IPVA' THEN 'directions_car'
  WHEN 'Licenciamento' THEN 'description'
  WHEN 'Multas' THEN 'warning'
  WHEN 'Financiamento do veículo' THEN 'car_rental'
END,
c.color = CASE c.name
  WHEN 'Combustível' THEN '#0277BD'
  WHEN 'Transporte público' THEN '#303F9F'
  WHEN 'Uber/99' THEN '#455A64'
  WHEN 'Estacionamento' THEN '#1565C0'
  WHEN 'Pedágio' THEN '#00838F'
  WHEN 'Manutenção' THEN '#5D4037'
  WHEN 'Seguro' THEN '#00796B'
  WHEN 'IPVA' THEN '#C62828'
  WHEN 'Licenciamento' THEN '#6A1B9A'
  WHEN 'Multas' THEN '#E64A19'
  WHEN 'Financiamento do veículo' THEN '#7B1FA2'
END;

-- ============ SAÚDE ============
UPDATE categories SET icon='local_hospital', color='#00796B' WHERE name='Saúde' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Saúde' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Plano de saúde' THEN 'health_and_safety'
  WHEN 'Consultas' THEN 'medical_services'
  WHEN 'Exames' THEN 'biotech'
  WHEN 'Medicamentos' THEN 'medication'
  WHEN 'Odontologia' THEN 'healing'
  WHEN 'Terapias' THEN 'psychology'
  WHEN 'Óculos e lentes' THEN 'visibility'
  WHEN 'Academia' THEN 'fitness_center'
  WHEN 'Outros cuidados de saúde' THEN 'favorite'
END,
c.color = CASE c.name
  WHEN 'Plano de saúde' THEN '#00796B'
  WHEN 'Consultas' THEN '#0288D1'
  WHEN 'Exames' THEN '#00897B'
  WHEN 'Medicamentos' THEN '#E53935'
  WHEN 'Odontologia' THEN '#5E35B1'
  WHEN 'Terapias' THEN '#8E24AA'
  WHEN 'Óculos e lentes' THEN '#3949AB'
  WHEN 'Academia' THEN '#F4511E'
  WHEN 'Outros cuidados de saúde' THEN '#D81B60'
END;

-- ============ COMPRAS ============
UPDATE categories SET icon='shopping_cart', color='#E64A19' WHERE name='Compras' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Compras' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Roupas' THEN 'checkroom'
  WHEN 'Calçados' THEN 'hiking'
  WHEN 'Eletrônicos' THEN 'devices'
  WHEN 'Celular' THEN 'smartphone'
  WHEN 'Computador' THEN 'computer'
  WHEN 'Casa' THEN 'weekend'
  WHEN 'Presentes' THEN 'redeem'
  WHEN 'Compras online' THEN 'local_mall'
  WHEN 'Outros' THEN 'more_horiz'
END,
c.color = CASE c.name
  WHEN 'Roupas' THEN '#AD1457'
  WHEN 'Calçados' THEN '#6D4C41'
  WHEN 'Eletrônicos' THEN '#3949AB'
  WHEN 'Celular' THEN '#00838F'
  WHEN 'Computador' THEN '#455A64'
  WHEN 'Casa' THEN '#8D6E63'
  WHEN 'Presentes' THEN '#7B1FA2'
  WHEN 'Compras online' THEN '#E64A19'
  WHEN 'Outros' THEN '#757575'
END;

-- ============ LAZER ============
UPDATE categories SET icon='sports_esports', color='#C2185B' WHERE name='Lazer e entretenimento' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Lazer e entretenimento' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Cinema' THEN 'movie'
  WHEN 'Shows' THEN 'mic'
  WHEN 'Eventos' THEN 'event'
  WHEN 'Viagens' THEN 'flight'
  WHEN 'Passeios' THEN 'park'
  WHEN 'Jogos' THEN 'sports_esports'
  WHEN 'Streaming' THEN 'live_tv'
  WHEN 'Música' THEN 'headphones'
  WHEN 'Livros' THEN 'menu_book'
  WHEN 'Hobbies' THEN 'palette'
  WHEN 'Esportes' THEN 'sports_soccer'
END,
c.color = CASE c.name
  WHEN 'Cinema' THEN '#5E35B1'
  WHEN 'Shows' THEN '#8E24AA'
  WHEN 'Eventos' THEN '#3949AB'
  WHEN 'Viagens' THEN '#039BE5'
  WHEN 'Passeios' THEN '#43A047'
  WHEN 'Jogos' THEN '#00897B'
  WHEN 'Streaming' THEN '#E53935'
  WHEN 'Música' THEN '#FB8C00'
  WHEN 'Livros' THEN '#6D4C41'
  WHEN 'Hobbies' THEN '#F4511E'
  WHEN 'Esportes' THEN '#7CB342'
END;

-- ============ ASSINATURAS ============
UPDATE categories SET icon='subscriptions', color='#5E35B1' WHERE name='Assinaturas e serviços digitais' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Assinaturas e serviços digitais' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Netflix' THEN 'smart_display'
  WHEN 'Spotify' THEN 'music_note'
  WHEN 'YouTube' THEN 'play_circle'
  WHEN 'Amazon Prime' THEN 'inventory_2'
  WHEN 'Disney+' THEN 'movie_creation'
  WHEN 'Game Pass' THEN 'videogame_asset'
  WHEN 'Armazenamento em nuvem' THEN 'cloud'
  WHEN 'Aplicativos' THEN 'apps'
  WHEN 'Softwares' THEN 'code'
  WHEN 'Inteligência artificial' THEN 'smart_toy'
END,
c.color = CASE c.name
  WHEN 'Netflix' THEN '#B71C1C'
  WHEN 'Spotify' THEN '#1DB954'
  WHEN 'YouTube' THEN '#FF0000'
  WHEN 'Amazon Prime' THEN '#00A8E1'
  WHEN 'Disney+' THEN '#113CCF'
  WHEN 'Game Pass' THEN '#107C10'
  WHEN 'Armazenamento em nuvem' THEN '#0288D1'
  WHEN 'Aplicativos' THEN '#8E24AA'
  WHEN 'Softwares' THEN '#455A64'
  WHEN 'Inteligência artificial' THEN '#5E35B1'
END;

-- ============ CUIDADOS PESSOAIS ============
UPDATE categories SET icon='spa', color='#AD1457' WHERE name='Cuidados pessoais' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Cuidados pessoais' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Cabeleireiro' THEN 'content_cut'
  WHEN 'Barbearia' THEN 'face'
  WHEN 'Cosméticos' THEN 'brush'
  WHEN 'Higiene pessoal' THEN 'soap'
  WHEN 'Estética' THEN 'self_improvement'
  WHEN 'Academia' THEN 'fitness_center'
  WHEN 'Roupas' THEN 'dry_cleaning'
  WHEN 'Outros' THEN 'more_horiz'
END,
c.color = CASE c.name
  WHEN 'Cabeleireiro' THEN '#AD1457'
  WHEN 'Barbearia' THEN '#5D4037'
  WHEN 'Cosméticos' THEN '#C2185B'
  WHEN 'Higiene pessoal' THEN '#0288D1'
  WHEN 'Estética' THEN '#8E24AA'
  WHEN 'Academia' THEN '#F4511E'
  WHEN 'Roupas' THEN '#6A1B9A'
  WHEN 'Outros' THEN '#757575'
END;

-- ============ EDUCAÇÃO ============
UPDATE categories SET icon='school', color='#512DA8' WHERE name='Educação' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Educação' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Faculdade' THEN 'history_edu'
  WHEN 'Cursos' THEN 'auto_stories'
  WHEN 'Certificações' THEN 'workspace_premium'
  WHEN 'Livros' THEN 'book'
  WHEN 'Material escolar' THEN 'backpack'
  WHEN 'Mensalidades' THEN 'payments'
  WHEN 'Cursos online' THEN 'cast_for_education'
  WHEN 'Idiomas' THEN 'translate'
END,
c.color = CASE c.name
  WHEN 'Faculdade' THEN '#512DA8'
  WHEN 'Cursos' THEN '#3949AB'
  WHEN 'Certificações' THEN '#F9A825'
  WHEN 'Livros' THEN '#6D4C41'
  WHEN 'Material escolar' THEN '#E64A19'
  WHEN 'Mensalidades' THEN '#00838F'
  WHEN 'Cursos online' THEN '#0277BD'
  WHEN 'Idiomas' THEN '#00897B'
END;

-- ============ PETS ============
UPDATE categories SET icon='pets', color='#795548' WHERE name='Pets' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Pets' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Ração' THEN 'rice_bowl'
  WHEN 'Veterinário' THEN 'vaccines'
  WHEN 'Medicamentos' THEN 'medication'
  WHEN 'Banho e tosa' THEN 'bathtub'
  WHEN 'Acessórios' THEN 'toys'
  WHEN 'Pet shop' THEN 'store'
  WHEN 'Plano veterinário' THEN 'monitor_heart'
END,
c.color = CASE c.name
  WHEN 'Ração' THEN '#795548'
  WHEN 'Veterinário' THEN '#00796B'
  WHEN 'Medicamentos' THEN '#E53935'
  WHEN 'Banho e tosa' THEN '#0288D1'
  WHEN 'Acessórios' THEN '#F9A825'
  WHEN 'Pet shop' THEN '#5D4037'
  WHEN 'Plano veterinário' THEN '#C2185B'
END;

-- ============ FAMÍLIA ============
UPDATE categories SET icon='family_restroom', color='#00897B' WHERE name='Família' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Família' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Filhos' THEN 'child_care'
  WHEN 'Escola' THEN 'school'
  WHEN 'Pensão' THEN 'request_quote'
  WHEN 'Cuidados com familiares' THEN 'elderly'
  WHEN 'Mesada' THEN 'savings'
  WHEN 'Presentes' THEN 'redeem'
  WHEN 'Despesas compartilhadas' THEN 'groups'
END,
c.color = CASE c.name
  WHEN 'Filhos' THEN '#F9A825'
  WHEN 'Escola' THEN '#512DA8'
  WHEN 'Pensão' THEN '#455A64'
  WHEN 'Cuidados com familiares' THEN '#8D6E63'
  WHEN 'Mesada' THEN '#388E3C'
  WHEN 'Presentes' THEN '#7B1FA2'
  WHEN 'Despesas compartilhadas' THEN '#00897B'
END;

-- ============ FINANCEIRO ============
UPDATE categories SET icon='account_balance', color='#455A64' WHERE name='Financeiro' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Financeiro' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Taxas bancárias' THEN 'account_balance'
  WHEN 'Tarifas' THEN 'receipt'
  WHEN 'Juros' THEN 'percent'
  WHEN 'Anuidade de cartão' THEN 'credit_card'
  WHEN 'IOF' THEN 'currency_exchange'
  WHEN 'Empréstimos' THEN 'money_off'
  WHEN 'Financiamentos' THEN 'real_estate_agent'
  WHEN 'Renegociação de dívidas' THEN 'handshake'
END,
c.color = CASE c.name
  WHEN 'Taxas bancárias' THEN '#455A64'
  WHEN 'Tarifas' THEN '#616161'
  WHEN 'Juros' THEN '#C62828'
  WHEN 'Anuidade de cartão' THEN '#6A1B9A'
  WHEN 'IOF' THEN '#F9A825'
  WHEN 'Empréstimos' THEN '#D84315'
  WHEN 'Financiamentos' THEN '#5D4037'
  WHEN 'Renegociação de dívidas' THEN '#00796B'
END;

-- ============ IMPOSTOS ============
UPDATE categories SET icon='gavel', color='#BF360C' WHERE name='Impostos e obrigações' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Impostos e obrigações' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Imposto de renda' THEN 'request_page'
  WHEN 'IPTU' THEN 'house'
  WHEN 'IPVA' THEN 'directions_car'
  WHEN 'Taxas públicas' THEN 'account_balance_wallet'
  WHEN 'Documentação' THEN 'badge'
  WHEN 'Multas' THEN 'gavel'
END,
c.color = CASE c.name
  WHEN 'Imposto de renda' THEN '#BF360C'
  WHEN 'IPTU' THEN '#6D4C41'
  WHEN 'IPVA' THEN '#1565C0'
  WHEN 'Taxas públicas' THEN '#455A64'
  WHEN 'Documentação' THEN '#00838F'
  WHEN 'Multas' THEN '#C62828'
END;

-- ============ DOAÇÕES ============
UPDATE categories SET icon='card_giftcard', color='#6D4C41' WHERE name='Doações e presentes' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Doações e presentes' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Presentes' THEN 'redeem'
  WHEN 'Doações' THEN 'volunteer_activism'
  WHEN 'Ajuda familiar' THEN 'family_restroom'
  WHEN 'Contribuições' THEN 'paid'
END,
c.color = CASE c.name
  WHEN 'Presentes' THEN '#7B1FA2'
  WHEN 'Doações' THEN '#D81B60'
  WHEN 'Ajuda familiar' THEN '#00897B'
  WHEN 'Contribuições' THEN '#388E3C'
END;

-- ============ OUTRAS DESPESAS ============
UPDATE categories SET icon='more_horiz', color='#607D8B' WHERE name='Outras despesas' AND type='expense';
UPDATE categories c JOIN categories p ON p.id=c.parent_id AND p.name='Outras despesas' AND p.type='expense'
SET c.icon = CASE c.name
  WHEN 'Despesas diversas' THEN 'more_horiz'
  WHEN 'Despesas emergenciais' THEN 'emergency'
  WHEN 'Não categorizado' THEN 'help'
END,
c.color = CASE c.name
  WHEN 'Despesas diversas' THEN '#607D8B'
  WHEN 'Despesas emergenciais' THEN '#E64A19'
  WHEN 'Não categorizado' THEN '#9E9E9E'
END;
