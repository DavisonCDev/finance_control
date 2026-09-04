-- Cartões de crédito completos: titular, adicionais, faturas, pagamento, estornos (spec §4)

ALTER TABLE credit_cards ADD COLUMN bank VARCHAR(80) NULL;
ALTER TABLE credit_cards ADD COLUMN holder_name VARCHAR(120) NULL;
ALTER TABLE credit_cards ADD COLUMN last_digits CHAR(4) NULL;
ALTER TABLE credit_cards ADD COLUMN color VARCHAR(7) NOT NULL DEFAULT '#1565C0';
ALTER TABLE credit_cards ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'BRL';
ALTER TABLE credit_cards ADD COLUMN parent_card_id INT NULL;
ALTER TABLE credit_cards ADD COLUMN is_additional BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE credit_cards ADD COLUMN default_account_id INT NULL;
ALTER TABLE credit_cards ADD CONSTRAINT fk_cards_parent FOREIGN KEY (parent_card_id) REFERENCES credit_cards(id) ON DELETE CASCADE;
ALTER TABLE credit_cards ADD CONSTRAINT fk_cards_account FOREIGN KEY (default_account_id) REFERENCES accounts(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS card_invoices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  card_id INT NOT NULL,
  reference_month VARCHAR(7) NOT NULL,
  closing_date DATE NOT NULL,
  due_date DATE NOT NULL,
  total_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  paid_amount DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  status ENUM('open','closed','partial','paid') NOT NULL DEFAULT 'open',
  paid_at DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_invoice (card_id, reference_month),
  KEY idx_invoices_user (user_id, due_date),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (card_id) REFERENCES credit_cards(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS invoice_payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  invoice_id INT NOT NULL,
  account_id INT NULL,
  transaction_id INT NULL,
  amount DECIMAL(15,2) NOT NULL,
  paid_at DATE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (invoice_id) REFERENCES card_invoices(id) ON DELETE CASCADE,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Compras no cartão pertencem a uma fatura; estornos são valores negativos do tipo refund
ALTER TABLE transactions ADD COLUMN invoice_id INT NULL;
ALTER TABLE transactions ADD COLUMN is_refund BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_invoice FOREIGN KEY (invoice_id) REFERENCES card_invoices(id) ON DELETE SET NULL;
