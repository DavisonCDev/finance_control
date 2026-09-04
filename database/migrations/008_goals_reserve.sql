-- Metas com aportes vinculados e reserva de emergência (spec §16, §40)

ALTER TABLE goals ADD COLUMN description VARCHAR(255) NULL;
ALTER TABLE goals ADD COLUMN icon VARCHAR(30) NOT NULL DEFAULT 'flag';
ALTER TABLE goals ADD COLUMN color VARCHAR(7) NOT NULL DEFAULT '#2E7D32';
ALTER TABLE goals ADD COLUMN kind ENUM('car','trip','house','emergency','device','college','wedding','investment','other') NOT NULL DEFAULT 'other';
ALTER TABLE goals ADD COLUMN monthly_contribution DECIMAL(15,2) NULL;
ALTER TABLE goals ADD COLUMN account_id INT NULL;
ALTER TABLE goals ADD COLUMN status ENUM('active','completed','cancelled') NOT NULL DEFAULT 'active';
ALTER TABLE goals ADD COLUMN completed_at DATETIME NULL;
ALTER TABLE goals ADD CONSTRAINT fk_goals_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS goal_contributions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  goal_id INT NOT NULL,
  user_id INT NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  date DATE NOT NULL,
  transaction_id INT NULL,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_contrib_goal (goal_id, date),
  FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS emergency_reserves (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  target_months TINYINT NOT NULL DEFAULT 6,
  monthly_expense_override DECIMAL(15,2) NULL,
  goal_id INT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_reserve (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL,
  FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
