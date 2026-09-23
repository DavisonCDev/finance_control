-- Estrutura Plano de Contas (PC), Metas Mensais e campos adicionais
-- Compatível com a planilha CONTROLE FINANCEIRO_2026_R1

-- ============================================================
-- 1. Categories: adicionar pc_code e pc_group para DRE/FC
-- ============================================================
ALTER TABLE categories
  ADD COLUMN pc_code VARCHAR(20) NULL COMMENT 'Codigo PC ex: 1.1.1, 2.1.3' AFTER sort_order,
  ADD COLUMN pc_group VARCHAR(40) NULL COMMENT 'Grupo DRE: Receita1..4, Custo1..3, Despesa1..5, Imposto, Investimento' AFTER pc_code;

CREATE INDEX idx_categories_pc_code ON categories(pc_code);
CREATE INDEX idx_categories_pc_group ON categories(pc_group);

-- ============================================================
-- 2. Transactions: adicionar classification, pc_reference, item (col D, E, F da planilha Jan)
-- ============================================================
ALTER TABLE transactions
  ADD COLUMN classification VARCHAR(255) NULL COMMENT 'Coluna D da planilha: Classificacao do item' AFTER contact_id,
  ADD COLUMN pc_reference VARCHAR(64) NULL COMMENT 'Coluna E: referencia PC ex: 2.1.3 LUZ' AFTER classification,
  ADD COLUMN item VARCHAR(255) NULL COMMENT 'Coluna F: item detalhado da transacao' AFTER pc_reference;

CREATE INDEX idx_tx_pc_reference ON transactions(pc_reference);

-- ============================================================
-- 3. Contacts: telefone, email, observacoes (PC_Cli)
-- ============================================================
ALTER TABLE contacts
  ADD COLUMN phone VARCHAR(30) NULL AFTER type,
  ADD COLUMN email VARCHAR(120) NULL AFTER phone,
  ADD COLUMN notes TEXT NULL AFTER email;

-- ============================================================
-- 4. Cost centers: ordenacao e codigo (PC_CC)
-- ============================================================
ALTER TABLE cost_centers
  ADD COLUMN sort_order INT NOT NULL DEFAULT 0 AFTER active,
  ADD COLUMN code VARCHAR(20) NULL AFTER sort_order;

-- ============================================================
-- 5. Payment methods: SIM, NAO, DEBITO, CREDITO, BOLETO, PARCELADO, DINHEIRO, VR
--    payment_method vira VARCHAR para aceitar os metodos da planilha
-- ============================================================
ALTER TABLE transactions
  MODIFY COLUMN payment_method VARCHAR(40) NOT NULL DEFAULT 'OTHER';

CREATE TABLE IF NOT EXISTS payment_methods (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NULL,
  name VARCHAR(40) NOT NULL,
  short_name VARCHAR(20) NULL,
  requires_bank BOOLEAN NOT NULL DEFAULT TRUE,
  is_credit BOOLEAN NOT NULL DEFAULT FALSE,
  is_cash BOOLEAN NOT NULL DEFAULT FALSE,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed de payment methods padrao da planilha
INSERT INTO payment_methods (user_id, name, short_name, requires_bank, is_credit, is_cash, is_system, sort_order) VALUES
  (NULL, 'SIM',          'SIM',     TRUE,  FALSE, FALSE, TRUE, 1),
  (NULL, 'NAO',          'NAO',     FALSE, FALSE, FALSE, TRUE, 2),
  (NULL, 'DEBITO',       'DEBITO',  TRUE,  FALSE, FALSE, TRUE, 3),
  (NULL, 'CREDITO',      'CREDITO', TRUE,  TRUE,  FALSE, TRUE, 4),
  (NULL, 'BOLETO',       'BOLETO',  TRUE,  FALSE, FALSE, TRUE, 5),
  (NULL, 'PARCELADO',    'PARC',    TRUE,  TRUE,  FALSE, TRUE, 6),
  (NULL, 'DINHEIRO',     'DINH',    FALSE, FALSE, TRUE,  TRUE, 7),
  (NULL, 'VR',           'VR',      FALSE, FALSE, TRUE,  TRUE, 8);

-- ============================================================
-- 6. Goals Monthly: Metas Mensais (aba Meta da planilha)
--    3 tipos: receita, despesa, resultado
-- ============================================================
CREATE TABLE IF NOT EXISTS goals_monthly (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  year INT NOT NULL,
  goal_type ENUM('receita','despesa','resultado') NOT NULL,
  month_1  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Jan',
  month_2  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Fev',
  month_3  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Mar',
  month_4  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Abr',
  month_5  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Mai',
  month_6  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Jun',
  month_7  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Jul',
  month_8  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Ago',
  month_9  DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Set',
  month_10 DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Out',
  month_11 DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Nov',
  month_12 DECIMAL(15,2) NOT NULL DEFAULT 0.00 COMMENT 'Dez',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_goals_monthly (user_id, year, goal_type),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
