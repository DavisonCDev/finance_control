-- Categorias padrão (com subcategorias) e conteúdos de educação financeira (spec §8, §44)

INSERT INTO categories (id, user_id, name, type, color, icon, is_system, sort_order) VALUES
  (1,  NULL, 'Salário',         'income',  '#2E7D32', 'work',            TRUE, 1),
  (2,  NULL, 'Freelance',       'income',  '#1976D2', 'computer',        TRUE, 2),
  (3,  NULL, 'Investimentos',   'income',  '#7B1FA2', 'trending_up',     TRUE, 3),
  (4,  NULL, 'Outras receitas', 'income',  '#388E3C', 'add_circle',      TRUE, 9),
  (5,  NULL, 'Moradia',         'expense', '#D32F2F', 'home',            TRUE, 1),
  (6,  NULL, 'Alimentação',     'expense', '#F57C00', 'restaurant',      TRUE, 2),
  (7,  NULL, 'Transporte',      'expense', '#0288D1', 'directions_car',  TRUE, 3),
  (8,  NULL, 'Lazer',           'expense', '#C2185B', 'sports_esports',  TRUE, 4),
  (9,  NULL, 'Saúde',           'expense', '#00796B', 'local_hospital',  TRUE, 5),
  (10, NULL, 'Educação',        'expense', '#512DA8', 'school',          TRUE, 6),
  (11, NULL, 'Contas',          'expense', '#FBC02D', 'receipt',         TRUE, 7),
  (12, NULL, 'Compras',         'expense', '#E64A19', 'shopping_cart',   TRUE, 8),
  (13, NULL, 'Outras despesas', 'expense', '#455A64', 'more_horiz',      TRUE, 9)
ON DUPLICATE KEY UPDATE is_system = TRUE, sort_order = VALUES(sort_order);

-- Categorias de receita que faltavam na spec §8
INSERT INTO categories (user_id, name, type, color, icon, is_system, sort_order) VALUES
  (NULL, 'Comissão', 'income', '#00838F', 'percent',       TRUE, 4),
  (NULL, 'Venda',    'income', '#5D4037', 'sell',          TRUE, 5),
  (NULL, 'Aluguel recebido', 'income', '#6A1B9A', 'home_work', TRUE, 6);

-- Subcategorias padrão
INSERT INTO categories (user_id, parent_id, name, type, color, icon, is_system, sort_order) VALUES
  (NULL, 5,  'Aluguel',          'expense', '#D32F2F', 'home',           TRUE, 1),
  (NULL, 5,  'Condomínio',       'expense', '#D32F2F', 'apartment',      TRUE, 2),
  (NULL, 5,  'Manutenção',       'expense', '#D32F2F', 'build',          TRUE, 3),
  (NULL, 6,  'Supermercado',     'expense', '#F57C00', 'shopping_basket',TRUE, 1),
  (NULL, 6,  'Restaurante',      'expense', '#F57C00', 'restaurant',     TRUE, 2),
  (NULL, 6,  'Delivery',         'expense', '#F57C00', 'delivery_dining',TRUE, 3),
  (NULL, 7,  'Combustível',      'expense', '#0288D1', 'local_gas_station', TRUE, 1),
  (NULL, 7,  'Aplicativos',      'expense', '#0288D1', 'local_taxi',     TRUE, 2),
  (NULL, 7,  'Transporte público','expense','#0288D1', 'directions_bus', TRUE, 3),
  (NULL, 7,  'Estacionamento',   'expense', '#0288D1', 'local_parking',  TRUE, 4),
  (NULL, 8,  'Streaming',        'expense', '#C2185B', 'live_tv',        TRUE, 1),
  (NULL, 8,  'Viagens',          'expense', '#C2185B', 'flight',         TRUE, 2),
  (NULL, 9,  'Farmácia',         'expense', '#00796B', 'local_pharmacy', TRUE, 1),
  (NULL, 9,  'Plano de saúde',   'expense', '#00796B', 'health_and_safety', TRUE, 2),
  (NULL, 9,  'Consultas',        'expense', '#00796B', 'medical_services', TRUE, 3),
  (NULL, 11, 'Energia',          'expense', '#FBC02D', 'bolt',           TRUE, 1),
  (NULL, 11, 'Água',             'expense', '#FBC02D', 'water_drop',     TRUE, 2),
  (NULL, 11, 'Internet',         'expense', '#FBC02D', 'wifi',           TRUE, 3),
  (NULL, 11, 'Telefone',         'expense', '#FBC02D', 'smartphone',     TRUE, 4),
  (NULL, 11, 'Assinaturas',      'expense', '#FBC02D', 'subscriptions',  TRUE, 5);

INSERT INTO education_contents (slug, category, title, summary, body, reading_minutes, sort_order) VALUES
  ('como-montar-um-orcamento', 'budget', 'Como montar um orçamento que funciona',
   'Aprenda a dividir sua renda entre despesas fixas, variáveis e reservas usando um método simples.',
   'Um orçamento é um plano, não uma prisão. Comece listando sua renda líquida mensal. Em seguida separe as despesas fixas (aluguel, energia, internet, escola), que costumam representar até 50% da renda. Depois as despesas variáveis (alimentação fora, lazer, compras), com limite de 30%. Os 20% restantes vão para reserva de emergência, quitação de dívidas e investimentos. Registre todos os lançamentos por pelo menos três meses antes de julgar os números: só com histórico você descobre onde o dinheiro realmente vai. Revise o orçamento no primeiro dia de cada mês e ajuste os limites por categoria conforme a realidade, não conforme o desejo.',
   4, 1),
  ('sair-das-dividas', 'debt', 'Saindo das dívidas: bola de neve x avalanche',
   'Duas estratégias comprovadas para eliminar dívidas e quando usar cada uma.',
   'Liste todas as dívidas com valor restante, taxa de juros e parcela. Na estratégia avalanche você paga primeiro a dívida de maior taxa de juros, o que minimiza o custo total. Na bola de neve você quita primeiro a menor dívida, gerando vitórias rápidas que sustentam a motivação. Matematicamente a avalanche vence; comportamentalmente a bola de neve costuma ter mais adesão. Em qualquer caso: pare de usar crédito rotativo, negocie taxas, e nunca troque uma dívida barata por uma mais cara e mais longa apenas para reduzir a parcela. Cheque o Custo Efetivo Total (CET) antes de aceitar qualquer refinanciamento.',
   5, 1),
  ('reserva-de-emergencia', 'emergency', 'Reserva de emergência: quanto e onde guardar',
   'Defina o tamanho ideal da sua reserva e os produtos adequados para ela.',
   'A reserva de emergência existe para você não recorrer a crédito caro em imprevistos. O tamanho depende da estabilidade da sua renda: assalariados com estabilidade costumam ficar bem com 6 meses de despesas essenciais; autônomos e PJ devem buscar de 9 a 12 meses. Calcule usando despesas essenciais, não a renda. O dinheiro precisa de liquidez diária e risco baixo — Tesouro Selic, CDBs de liquidez diária com FGC ou fundos DI de taxa baixa. Nunca coloque a reserva em ações, cripto ou imóveis. Reponha o valor sempre que usar.',
   4, 1),
  ('primeiros-investimentos', 'investments', 'Primeiros investimentos: por onde começar',
   'A ordem lógica entre reserva, renda fixa e renda variável.',
   'Antes de investir, quite dívidas caras e monte a reserva de emergência: nenhum investimento rende mais do que os juros do rotativo do cartão. Com a reserva pronta, defina objetivos com prazo. Objetivos de curto prazo pedem renda fixa pós-fixada e liquidez. Metas de médio prazo aceitam prefixados e IPCA+ com vencimento próximo ao objetivo. Só o dinheiro de longo prazo, que você não vai precisar em anos, deve ir para renda variável (ações, ETFs, FIIs), sempre diversificado. Acompanhe rentabilidade real (descontada a inflação) e evite trocar de estratégia por notícia do dia.',
   5, 1),
  ('usar-cartao-sem-se-perder', 'credit_card', 'Cartão de crédito sem se perder',
   'Como aproveitar o cartão como ferramenta e não como armadilha.',
   'O cartão de crédito é um instrumento de prazo, não de renda extra. Regra base: só compre no cartão o que você já tem dinheiro para pagar hoje. Acompanhe o limite utilizado e não a fatura fechada — o gasto do dia já compromete o mês seguinte. Evite parcelar sem juros por prazos longos, porque as parcelas se acumulam e travam seu orçamento futuro. Jamais pague o mínimo: o rotativo é uma das linhas de crédito mais caras do mercado. Configure o vencimento poucos dias depois de receber o salário e mantenha um único cartão principal, se possível.',
   4, 1),
  ('financiamento-imobiliario', 'financing', 'Financiamento: SAC ou Price?',
   'Entenda a diferença entre os sistemas de amortização e o impacto no total pago.',
   'No sistema SAC a amortização é constante e as parcelas começam mais altas e caem ao longo do tempo. No Price a parcela é fixa, mas você amortiza pouco no começo e paga mais juros no total. Se o seu orçamento suporta a parcela inicial, o SAC tende a custar menos. Independentemente do sistema, amortizações extraordinárias abatendo o saldo devedor (e não as próximas parcelas) reduzem drasticamente os juros. Compare sempre o CET entre bancos e considere os custos acessórios: seguros, taxa de administração e avaliação do imóvel.',
   5, 1),
  ('juros-compostos', 'interest', 'Juros compostos: seu maior aliado ou seu pior inimigo',
   'O mesmo mecanismo que multiplica investimentos é o que faz dívidas explodirem.',
   'Juros compostos incidem sobre o saldo acumulado, não apenas sobre o valor inicial. R$ 500 por mês a 0,8% ao mês viram cerca de R$ 91 mil em 10 anos, sendo R$ 31 mil só de juros. O efeito é simétrico: uma dívida de rotativo a 14% ao mês dobra em cerca de 5 meses. Duas variáveis dominam o resultado: tempo e taxa. Por isso começar cedo vale mais que aportar muito, e quitar dívidas caras rende mais que qualquer investimento conservador. Use a regra dos 72 para estimativas rápidas: 72 dividido pela taxa mensal dá o número de meses para dobrar o valor.',
   4, 1),
  ('planejamento-de-longo-prazo', 'planning', 'Planejamento financeiro de longo prazo',
   'Como transformar objetivos de vida em metas financeiras mensuráveis.',
   'Planejamento começa com objetivos concretos: valor, prazo e prioridade. Transforme cada objetivo em um aporte mensal (valor dividido pelo número de meses, ajustado por rentabilidade esperada). Some os aportes: se ultrapassarem sua capacidade de poupança, é preciso repriorizar, esticar prazos ou aumentar renda — não ignorar. Revise o plano a cada semestre e sempre que houver mudança relevante de renda, composição familiar ou moradia. Acompanhe dois indicadores mensais: taxa de poupança (quanto sobra da renda) e patrimônio líquido (ativos menos passivos). São eles que mostram se você está avançando.',
   5, 1);
