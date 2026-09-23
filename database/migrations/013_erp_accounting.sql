-- Evolucao para regime de caixa x competencia (ERP leve).

-- Centros de custo
CREATE TABLE IF NOT EXISTS cost_centers (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clientes e fornecedores
CREATE TABLE IF NOT EXISTS contacts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  type ENUM('customer','supplier','other') DEFAULT 'other',
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Datas e pagamento nas transacoes
ALTER TABLE transactions
  ADD COLUMN accrual_date DATE NULL AFTER date,
  ADD COLUMN payment_date DATE NULL AFTER accrual_date,
  ADD COLUMN is_paid BOOLEAN NOT NULL DEFAULT TRUE AFTER payment_date,
  ADD COLUMN payment_method ENUM('PIX','BOLETO','TED','CREDIT_CARD','CASH','OTHER') DEFAULT 'OTHER' AFTER is_paid,
  ADD COLUMN cost_center_id INT NULL AFTER payment_method,
  ADD COLUMN contact_id INT NULL AFTER cost_center_id;

UPDATE transactions SET accrual_date = date WHERE accrual_date IS NULL;
UPDATE transactions SET payment_date = date WHERE payment_date IS NULL;
UPDATE transactions SET is_paid = (status = 'cleared') WHERE is_paid = TRUE;

ALTER TABLE transactions
  ADD FOREIGN KEY (cost_center_id) REFERENCES cost_centers(id) ON DELETE SET NULL,
  ADD FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL;

-- Meta esperada no orcamento
ALTER TABLE budgets
  ADD COLUMN expected_value DECIMAL(15,2) NOT NULL DEFAULT 0.00 AFTER amount,
  ADD COLUMN achieved_percent DECIMAL(5,2) NULL AFTER expected_value;
