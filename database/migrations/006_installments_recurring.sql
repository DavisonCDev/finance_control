-- Parcelamentos com parcelas individuais e recorrências completas (spec §6, §7)

ALTER TABLE installments ADD COLUMN card_id INT NULL;
ALTER TABLE installments ADD COLUMN purchase_date DATE NULL;
ALTER TABLE installments ADD COLUMN paid_installments INT NOT NULL DEFAULT 0;
ALTER TABLE installments ADD COLUMN status ENUM('active','completed','cancelled') NOT NULL DEFAULT 'active';
ALTER TABLE installments ADD COLUMN notes VARCHAR(255) NULL;
ALTER TABLE installments ADD CONSTRAINT fk_installments_card FOREIGN KEY (card_id) REFERENCES credit_cards(id) ON DELETE SET NULL;
ALTER TABLE installments ADD CONSTRAINT fk_installments_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL;
ALTER TABLE installments ADD CONSTRAINT fk_installments_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS installment_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  installment_id INT NOT NULL,
  number INT NOT NULL,
  due_date DATE NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  paid BOOLEAN NOT NULL DEFAULT FALSE,
  paid_at DATE NULL,
  transaction_id INT NULL,
  cancelled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_item (installment_id, number),
  FOREIGN KEY (installment_id) REFERENCES installments(id) ON DELETE CASCADE,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE transactions ADD CONSTRAINT fk_tx_installment FOREIGN KEY (installment_id) REFERENCES installments(id) ON DELETE SET NULL;

-- Periodicidades completas da spec §6
ALTER TABLE recurring_transactions
  MODIFY COLUMN frequency ENUM('daily','weekly','biweekly','monthly','bimonthly','quarterly','semiannual','yearly') NOT NULL DEFAULT 'monthly';
ALTER TABLE recurring_transactions ADD COLUMN card_id INT NULL;
ALTER TABLE recurring_transactions ADD COLUMN occurrences INT NULL;
ALTER TABLE recurring_transactions ADD COLUMN occurrences_done INT NOT NULL DEFAULT 0;
ALTER TABLE recurring_transactions ADD COLUMN auto_generate BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE recurring_transactions ADD COLUMN last_run_at DATETIME NULL;
ALTER TABLE recurring_transactions ADD COLUMN family_id INT NULL;
ALTER TABLE recurring_transactions ADD CONSTRAINT fk_recurring_card FOREIGN KEY (card_id) REFERENCES credit_cards(id) ON DELETE SET NULL;
ALTER TABLE recurring_transactions ADD CONSTRAINT fk_recurring_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;
