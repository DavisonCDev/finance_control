-- Lançamentos completos, subcategorias, tags, transferências e comprovantes
-- (spec §5, §8, §20, §24, §25, §26)

-- Subcategorias, ordenação e categoria de sistema
ALTER TABLE categories ADD COLUMN parent_id INT NULL;
ALTER TABLE categories ADD COLUMN sort_order INT NOT NULL DEFAULT 0;
ALTER TABLE categories ADD COLUMN is_system BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE categories ADD CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE CASCADE;

-- Lançamento: hora, local, moeda, status, transferência, vínculos
ALTER TABLE transactions ADD COLUMN time TIME NULL;
ALTER TABLE transactions ADD COLUMN location VARCHAR(180) NULL;
ALTER TABLE transactions ADD COLUMN latitude DECIMAL(10,7) NULL;
ALTER TABLE transactions ADD COLUMN longitude DECIMAL(10,7) NULL;
ALTER TABLE transactions ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'BRL';
ALTER TABLE transactions ADD COLUMN original_amount DECIMAL(15,2) NULL;
ALTER TABLE transactions ADD COLUMN exchange_rate DECIMAL(15,6) NULL;
ALTER TABLE transactions ADD COLUMN status ENUM('pending','cleared','scheduled','cancelled') NOT NULL DEFAULT 'cleared';
ALTER TABLE transactions ADD COLUMN transfer_account_id INT NULL;
ALTER TABLE transactions ADD COLUMN transfer_pair_id INT NULL;
ALTER TABLE transactions ADD COLUMN transfer_to_user_id INT NULL;
ALTER TABLE transactions ADD COLUMN installment_id INT NULL;
ALTER TABLE transactions ADD COLUMN installment_number INT NULL;
ALTER TABLE transactions ADD COLUMN recurring_id INT NULL;
ALTER TABLE transactions ADD COLUMN goal_id INT NULL;
ALTER TABLE transactions ADD COLUMN import_hash CHAR(40) NULL;
ALTER TABLE transactions ADD COLUMN client_uuid CHAR(36) NULL;
ALTER TABLE transactions ADD COLUMN source ENUM('manual','import','recurring','installment','ocr','rule','open_finance','automation') NOT NULL DEFAULT 'manual';
ALTER TABLE transactions ADD COLUMN updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;
ALTER TABLE transactions ADD COLUMN deleted_at DATETIME NULL;

ALTER TABLE transactions ADD CONSTRAINT fk_tx_transfer_account FOREIGN KEY (transfer_account_id) REFERENCES accounts(id) ON DELETE SET NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_transfer_user FOREIGN KEY (transfer_to_user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_recurring FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id) ON DELETE SET NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_goal FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE SET NULL;

-- Dedupe de importação e idempotência de sincronização offline
CREATE UNIQUE INDEX idx_tx_import_hash ON transactions (user_id, import_hash);
CREATE UNIQUE INDEX idx_tx_client_uuid ON transactions (user_id, client_uuid);
CREATE INDEX idx_tx_user_date ON transactions (user_id, date);
CREATE INDEX idx_tx_description ON transactions (description);

CREATE TABLE IF NOT EXISTS tags (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(40) NOT NULL,
  color VARCHAR(7) NOT NULL DEFAULT '#607D8B',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_tag (user_id, name),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS transaction_tags (
  transaction_id INT NOT NULL,
  tag_id INT NOT NULL,
  PRIMARY KEY (transaction_id, tag_id),
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Comprovantes: fotos, PDFs, notas fiscais, PIX, recibos
CREATE TABLE IF NOT EXISTS attachments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  transaction_id INT NULL,
  kind ENUM('photo','pdf','invoice','pix_receipt','receipt','other') NOT NULL DEFAULT 'other',
  file_name VARCHAR(255) NOT NULL,
  stored_name VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NULL,
  size_bytes INT NULL,
  ocr_text TEXT NULL,
  ocr_status ENUM('none','pending','done','failed') NOT NULL DEFAULT 'none',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_attachments_tx (transaction_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Múltiplas moedas (spec §26)
CREATE TABLE IF NOT EXISTS currencies (
  code CHAR(3) PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  symbol VARCHAR(6) NOT NULL,
  decimal_places TINYINT NOT NULL DEFAULT 2
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO currencies (code, name, symbol) VALUES
  ('BRL', 'Real brasileiro', 'R$'),
  ('USD', 'Dólar americano', 'US$'),
  ('EUR', 'Euro', '€'),
  ('GBP', 'Libra esterlina', '£'),
  ('ARS', 'Peso argentino', '$'),
  ('JPY', 'Iene japonês', '¥'),
  ('CHF', 'Franco suíço', 'CHF'),
  ('CAD', 'Dólar canadense', 'C$');

CREATE TABLE IF NOT EXISTS exchange_rates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  base_code CHAR(3) NOT NULL,
  quote_code CHAR(3) NOT NULL,
  rate DECIMAL(18,8) NOT NULL,
  rate_date DATE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_rate (base_code, quote_code, rate_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE accounts ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'BRL';
ALTER TABLE accounts MODIFY COLUMN type ENUM('checking','savings','digital','cash','investment','salary','joint','international','other') NOT NULL DEFAULT 'checking';
