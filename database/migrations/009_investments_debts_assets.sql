-- Investimentos, dívidas e patrimônio (spec §17, §18, §19)

CREATE TABLE IF NOT EXISTS investments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  account_id INT NULL,
  name VARCHAR(120) NOT NULL,
  type ENUM('treasury','cdb','lci_lca','stock','etf','reit','crypto','fund','savings','pension','other') NOT NULL DEFAULT 'other',
  broker VARCHAR(80) NULL,
  ticker VARCHAR(20) NULL,
  invested_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  current_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  quantity DECIMAL(18,8) NULL,
  currency CHAR(3) NOT NULL DEFAULT 'BRL',
  purchase_date DATE NULL,
  maturity_date DATE NULL,
  notes VARCHAR(255) NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_investments_user (user_id, active),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS investment_movements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  investment_id INT NOT NULL,
  kind ENUM('contribution','withdrawal','dividend','yield','fee','tax','valuation') NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  quantity DECIMAL(18,8) NULL,
  unit_price DECIMAL(18,8) NULL,
  date DATE NOT NULL,
  transaction_id INT NULL,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_movements_investment (investment_id, date),
  FOREIGN KEY (investment_id) REFERENCES investments(id) ON DELETE CASCADE,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS debts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  name VARCHAR(120) NOT NULL,
  type ENUM('loan','financing','personal','card','installment','overdraft','other') NOT NULL DEFAULT 'other',
  creditor VARCHAR(120) NULL,
  original_amount DECIMAL(15,2) NOT NULL,
  paid_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  interest_rate DECIMAL(8,4) NULL,
  total_installments INT NULL,
  paid_installments INT NOT NULL DEFAULT 0,
  installment_amount DECIMAL(15,2) NULL,
  start_date DATE NULL,
  due_day TINYINT NULL,
  next_due_date DATE NULL,
  card_id INT NULL,
  status ENUM('active','paid','renegotiated','defaulted') NOT NULL DEFAULT 'active',
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_debts_user (user_id, status),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL,
  FOREIGN KEY (card_id) REFERENCES credit_cards(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS debt_payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  debt_id INT NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  date DATE NOT NULL,
  transaction_id INT NULL,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_debt_payments (debt_id, date),
  FOREIGN KEY (debt_id) REFERENCES debts(id) ON DELETE CASCADE,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS assets (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  name VARCHAR(120) NOT NULL,
  type ENUM('vehicle','property','equipment','valuable','receivable','other') NOT NULL DEFAULT 'other',
  value DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  acquisition_value DECIMAL(15,2) NULL,
  acquisition_date DATE NULL,
  depreciation_rate DECIMAL(8,4) NULL,
  notes VARCHAR(255) NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_assets_user (user_id, active),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS net_worth_snapshots (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  snapshot_date DATE NOT NULL,
  accounts_total DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  investments_total DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  assets_total DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  debts_total DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  cards_total DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  net_worth DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_snapshot (user_id, snapshot_date),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE transactions ADD COLUMN investment_id INT NULL;
ALTER TABLE transactions ADD COLUMN debt_id INT NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_investment FOREIGN KEY (investment_id) REFERENCES investments(id) ON DELETE SET NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_debt FOREIGN KEY (debt_id) REFERENCES debts(id) ON DELETE SET NULL;
