-- Administração, monetização, gamificação, educação financeira e Open Finance
-- (spec §29, §32, §33, §43, §44, §46, §47)

CREATE TABLE IF NOT EXISTS plans (
  code VARCHAR(30) PRIMARY KEY,
  name VARCHAR(60) NOT NULL,
  price_monthly DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  price_yearly DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  max_accounts INT NULL,
  max_cards INT NULL,
  max_family_members INT NULL,
  features JSON NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO plans (code, name, price_monthly, price_yearly, max_accounts, max_cards, max_family_members, features) VALUES
  ('free', 'Gratuito', 0.00, 0.00, 3, 1, 1,
   JSON_ARRAY('accounts','categories','transactions','basic_reports','budgets')),
  ('premium', 'Premium', 19.90, 199.00, NULL, NULL, 1,
   JSON_ARRAY('accounts','categories','transactions','advanced_reports','budgets','goals','investments','debts','assets','ai','ocr','export','open_finance','unlimited_cards')),
  ('family_premium', 'Família Premium', 29.90, 299.00, NULL, NULL, 10,
   JSON_ARRAY('accounts','categories','transactions','advanced_reports','budgets','goals','investments','debts','assets','ai','ocr','export','open_finance','unlimited_cards','family','advanced_permissions','family_dashboard'));

CREATE TABLE IF NOT EXISTS subscriptions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  plan_code VARCHAR(30) NOT NULL,
  status ENUM('trialing','active','past_due','cancelled','expired') NOT NULL DEFAULT 'active',
  billing_cycle ENUM('monthly','yearly') NOT NULL DEFAULT 'monthly',
  started_at DATETIME NOT NULL,
  expires_at DATETIME NULL,
  cancelled_at DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_subscriptions_user (user_id, status),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_code) REFERENCES plans(code) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS error_logs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NULL,
  level ENUM('warn','error','fatal') NOT NULL DEFAULT 'error',
  message VARCHAR(500) NOT NULL,
  stack TEXT NULL,
  route VARCHAR(180) NULL,
  method VARCHAR(10) NULL,
  status_code INT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_errors_created (created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS support_tickets (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  subject VARCHAR(180) NOT NULL,
  message TEXT NOT NULL,
  status ENUM('open','in_progress','resolved','closed') NOT NULL DEFAULT 'open',
  response TEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS achievements (
  code VARCHAR(40) PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  description VARCHAR(255) NOT NULL,
  icon VARCHAR(30) NOT NULL DEFAULT 'emoji_events',
  points INT NOT NULL DEFAULT 10,
  target INT NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO achievements (code, name, description, icon, points, target) VALUES
  ('first_transaction', 'Primeiro passo', 'Registre seu primeiro lançamento', 'flag', 10, 1),
  ('streak_7', 'Uma semana firme', 'Registre lançamentos por 7 dias seguidos', 'local_fire_department', 30, 7),
  ('streak_30', 'Mês completo', 'Registre lançamentos por 30 dias seguidos', 'whatshot', 100, 30),
  ('budget_respected', 'Dentro do orçamento', 'Feche um mês sem estourar nenhum orçamento', 'savings', 50, 1),
  ('goal_completed', 'Meta batida', 'Conclua uma meta financeira', 'emoji_events', 80, 1),
  ('emergency_reserve', 'Rede de proteção', 'Complete sua reserva de emergência', 'shield', 150, 1),
  ('debt_free', 'Livre de dívidas', 'Quite todas as suas dívidas', 'celebration', 200, 1),
  ('first_investment', 'Investidor iniciante', 'Cadastre seu primeiro investimento', 'trending_up', 40, 1);

CREATE TABLE IF NOT EXISTS user_achievements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  achievement_code VARCHAR(40) NOT NULL,
  progress INT NOT NULL DEFAULT 0,
  earned_at DATETIME NULL,
  UNIQUE KEY unique_user_achievement (user_id, achievement_code),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (achievement_code) REFERENCES achievements(code) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_streaks (
  user_id INT PRIMARY KEY,
  current_streak INT NOT NULL DEFAULT 0,
  longest_streak INT NOT NULL DEFAULT 0,
  last_entry_date DATE NULL,
  total_points INT NOT NULL DEFAULT 0,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS family_challenges (
  id INT AUTO_INCREMENT PRIMARY KEY,
  family_id INT NOT NULL,
  created_by INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  description VARCHAR(255) NULL,
  kind ENUM('save_amount','reduce_category','no_spend_days') NOT NULL DEFAULT 'save_amount',
  target_amount DECIMAL(15,2) NULL,
  category_id INT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  status ENUM('active','completed','failed','cancelled') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS education_contents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  slug VARCHAR(80) NOT NULL UNIQUE,
  category ENUM('budget','debt','emergency','investments','credit_card','financing','interest','planning') NOT NULL,
  title VARCHAR(180) NOT NULL,
  summary VARCHAR(400) NOT NULL,
  body TEXT NOT NULL,
  reading_minutes TINYINT NOT NULL DEFAULT 3,
  sort_order INT NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Open Finance / integração bancária (spec §29)
CREATE TABLE IF NOT EXISTS bank_connections (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  institution VARCHAR(120) NOT NULL,
  institution_code VARCHAR(20) NULL,
  status ENUM('pending','active','expired','revoked','error') NOT NULL DEFAULT 'pending',
  consent_id VARCHAR(120) NULL,
  consent_expires_at DATETIME NULL,
  last_sync_at DATETIME NULL,
  last_error VARCHAR(255) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS bank_account_links (
  id INT AUTO_INCREMENT PRIMARY KEY,
  connection_id INT NOT NULL,
  external_id VARCHAR(120) NOT NULL,
  account_id INT NULL,
  card_id INT NULL,
  external_name VARCHAR(120) NULL,
  UNIQUE KEY unique_link (connection_id, external_id),
  FOREIGN KEY (connection_id) REFERENCES bank_connections(id) ON DELETE CASCADE,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  FOREIGN KEY (card_id) REFERENCES credit_cards(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sincronização / modo offline (spec §32, §33)
CREATE TABLE IF NOT EXISTS sync_state (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  device_id VARCHAR(80) NOT NULL,
  last_synced_at DATETIME NULL,
  UNIQUE KEY unique_sync (user_id, device_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
