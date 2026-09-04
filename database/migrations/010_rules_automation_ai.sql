-- Regras automáticas, automações, insights e IA (spec §21, §22, §34, §35)

CREATE TABLE IF NOT EXISTS auto_rules (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  priority INT NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  match_field ENUM('description','amount','account','card','type','category') NOT NULL DEFAULT 'description',
  match_operator ENUM('contains','not_contains','equals','starts_with','ends_with','greater_than','less_than','regex') NOT NULL DEFAULT 'contains',
  match_value VARCHAR(180) NOT NULL,
  action_type ENUM('set_category','add_tag','set_account','set_card','require_confirmation','link_invoice','mark_transfer','set_description') NOT NULL,
  action_value VARCHAR(180) NULL,
  stop_processing BOOLEAN NOT NULL DEFAULT FALSE,
  times_applied INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_rules_user (user_id, active, priority),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS automations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  type ENUM('recurring_generate','goal_contribution','invoice_close','notification_scan','net_worth_snapshot','backup','report') NOT NULL,
  config JSON NULL,
  frequency ENUM('daily','weekly','monthly') NOT NULL DEFAULT 'monthly',
  day_of_month TINYINT NULL,
  next_run_at DATETIME NULL,
  last_run_at DATETIME NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_automations_next (active, next_run_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS automation_runs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  automation_id INT NOT NULL,
  status ENUM('success','failed','skipped') NOT NULL,
  message VARCHAR(255) NULL,
  affected_rows INT NOT NULL DEFAULT 0,
  run_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_runs_automation (automation_id, run_at),
  FOREIGN KEY (automation_id) REFERENCES automations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS insights (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  family_id INT NULL,
  type ENUM('spending_spike','subscription_detected','category_trend','saving_suggestion','balance_forecast','budget_risk','income_missing','comparison') NOT NULL,
  title VARCHAR(180) NOT NULL,
  message TEXT NOT NULL,
  severity ENUM('info','warning','critical') NOT NULL DEFAULT 'info',
  reference_month VARCHAR(7) NULL,
  data JSON NULL,
  dismissed_at DATETIME NULL,
  dedupe_key VARCHAR(140) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_insight (user_id, dedupe_key),
  KEY idx_insights_user (user_id, created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS assistant_queries (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  question VARCHAR(500) NOT NULL,
  intent VARCHAR(60) NULL,
  answer TEXT NULL,
  data JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_queries_user (user_id, created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Assinaturas recorrentes detectadas automaticamente (spec §22)
CREATE TABLE IF NOT EXISTS detected_subscriptions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  merchant VARCHAR(180) NOT NULL,
  average_amount DECIMAL(15,2) NOT NULL,
  occurrences INT NOT NULL DEFAULT 0,
  first_seen DATE NULL,
  last_seen DATE NULL,
  interval_days INT NULL,
  category_id INT NULL,
  confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  ignored BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_subscription (user_id, merchant),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
