-- Família, permissões, compartilhamento seletivo, dependentes e feed (spec §2, §36, §37, §38)

ALTER TABLE families ADD COLUMN invite_code CHAR(8) NULL;
ALTER TABLE families ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'BRL';
CREATE UNIQUE INDEX idx_families_invite_code ON families (invite_code);

ALTER TABLE family_members MODIFY COLUMN role ENUM('admin','member','viewer','dependent') NOT NULL DEFAULT 'member';
ALTER TABLE family_members ADD COLUMN monthly_allowance DECIMAL(15,2) NULL;
ALTER TABLE family_members ADD COLUMN can_view_all BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE family_members ADD COLUMN can_manage_budget BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE family_members ADD COLUMN nickname VARCHAR(60) NULL;

CREATE TABLE IF NOT EXISTS family_invites (
  id INT AUTO_INCREMENT PRIMARY KEY,
  family_id INT NOT NULL,
  invited_by INT NOT NULL,
  email VARCHAR(120) NOT NULL,
  role ENUM('admin','member','viewer','dependent') NOT NULL DEFAULT 'member',
  token CHAR(32) NOT NULL,
  status ENUM('pending','accepted','declined','cancelled','expired') NOT NULL DEFAULT 'pending',
  expires_at DATETIME NULL,
  responded_at DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_invite_token (token),
  KEY idx_invites_email (email, status),
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (invited_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Compartilhamento seletivo: quais membros veem cada conta/cartão
CREATE TABLE IF NOT EXISTS resource_permissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  family_id INT NOT NULL,
  user_id INT NOT NULL,
  resource_type ENUM('account','card','budget','goal','investment','debt') NOT NULL,
  resource_id INT NOT NULL,
  can_view BOOLEAN NOT NULL DEFAULT TRUE,
  can_edit BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_permission (family_id, user_id, resource_type, resource_id),
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS family_activity (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  family_id INT NOT NULL,
  user_id INT NOT NULL,
  action ENUM('transaction_created','bill_paid','goal_contribution','budget_changed','member_joined','member_left','card_paid','other') NOT NULL,
  entity VARCHAR(40) NULL,
  entity_id INT NULL,
  description VARCHAR(255) NULL,
  amount DECIMAL(15,2) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_activity_family (family_id, created_at),
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Escopo familiar nos recursos financeiros
ALTER TABLE accounts ADD COLUMN family_id INT NULL;
ALTER TABLE accounts ADD COLUMN shared BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE accounts ADD CONSTRAINT fk_accounts_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;

ALTER TABLE credit_cards ADD COLUMN family_id INT NULL;
ALTER TABLE credit_cards ADD COLUMN shared BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE credit_cards ADD CONSTRAINT fk_cards_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;

ALTER TABLE transactions ADD COLUMN family_id INT NULL;
ALTER TABLE transactions ADD COLUMN person_id INT NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;
ALTER TABLE transactions ADD CONSTRAINT fk_tx_person FOREIGN KEY (person_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE budgets ADD COLUMN family_id INT NULL;
ALTER TABLE budgets ADD CONSTRAINT fk_budgets_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;

ALTER TABLE goals ADD COLUMN family_id INT NULL;
ALTER TABLE goals ADD CONSTRAINT fk_goals_family FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL;
