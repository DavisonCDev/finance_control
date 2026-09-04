-- Orçamento com alertas, planejamento mensal e notificações completas (spec §9, §10, §14)

ALTER TABLE budgets ADD COLUMN alert_threshold TINYINT NOT NULL DEFAULT 80;
ALTER TABLE budgets ADD COLUMN rollover BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE budgets ADD COLUMN notified_near_at DATETIME NULL;
ALTER TABLE budgets ADD COLUMN notified_over_at DATETIME NULL;

CREATE TABLE IF NOT EXISTS monthly_plans (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  plan_month VARCHAR(7) NOT NULL,
  expected_income DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  expected_expense DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  notes TEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_plan (user_id, plan_month),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS monthly_plan_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  plan_id INT NOT NULL,
  category_id INT NULL,
  kind ENUM('income','expense') NOT NULL,
  description VARCHAR(180) NULL,
  expected_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  FOREIGN KEY (plan_id) REFERENCES monthly_plans(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tipos de notificação da spec §14
ALTER TABLE notifications
  MODIFY COLUMN type ENUM(
    'budget_near','budget_over','bill_due','card_due','invoice_closed','low_balance',
    'installment_due','income_missing','family_expense','family_budget','family_event',
    'goal','insight','system','budget','bill','other'
  ) NOT NULL DEFAULT 'other';
ALTER TABLE notifications ADD COLUMN severity ENUM('info','warning','critical') NOT NULL DEFAULT 'info';
ALTER TABLE notifications ADD COLUMN entity VARCHAR(40) NULL;
ALTER TABLE notifications ADD COLUMN entity_id INT NULL;
ALTER TABLE notifications ADD COLUMN dedupe_key VARCHAR(120) NULL;
ALTER TABLE notifications ADD COLUMN sent_at DATETIME NULL;
CREATE UNIQUE INDEX idx_notifications_dedupe ON notifications (user_id, dedupe_key);

ALTER TABLE financial_events ADD COLUMN account_id INT NULL;
ALTER TABLE financial_events ADD COLUMN category_id INT NULL;
ALTER TABLE financial_events ADD COLUMN card_id INT NULL;
ALTER TABLE financial_events ADD COLUMN family_id INT NULL;
ALTER TABLE financial_events ADD COLUMN recurring_id INT NULL;
ALTER TABLE financial_events ADD COLUMN transaction_id INT NULL;
ALTER TABLE financial_events ADD COLUMN direction ENUM('income','expense') NOT NULL DEFAULT 'expense';
ALTER TABLE financial_events ADD CONSTRAINT fk_events_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL;
ALTER TABLE financial_events ADD CONSTRAINT fk_events_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE financial_events ADD CONSTRAINT fk_events_card FOREIGN KEY (card_id) REFERENCES credit_cards(id) ON DELETE SET NULL;
ALTER TABLE financial_events ADD CONSTRAINT fk_events_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;
ALTER TABLE financial_events ADD CONSTRAINT fk_events_transaction FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL;
