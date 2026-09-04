-- Perfil do usuário, preferências, segurança, sessões e auditoria (spec §1, §15, §45)
-- Um ALTER por coluna: o runner tolera "coluna já existe" e converge bancos alterados à mão.

ALTER TABLE users ADD COLUMN phone VARCHAR(30) NULL;
ALTER TABLE users ADD COLUMN photo_url VARCHAR(500) NULL;
ALTER TABLE users ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'BRL';
ALTER TABLE users ADD COLUMN country CHAR(2) NOT NULL DEFAULT 'BR';
ALTER TABLE users ADD COLUMN language VARCHAR(10) NOT NULL DEFAULT 'pt_BR';
ALTER TABLE users ADD COLUMN timezone VARCHAR(60) NOT NULL DEFAULT 'America/Sao_Paulo';
ALTER TABLE users ADD COLUMN first_day_of_month TINYINT NOT NULL DEFAULT 1;
ALTER TABLE users ADD COLUMN date_format VARCHAR(20) NOT NULL DEFAULT 'dd/MM/yyyy';
ALTER TABLE users ADD COLUMN theme ENUM('system','light','dark') NOT NULL DEFAULT 'system';
ALTER TABLE users ADD COLUMN privacy_mode BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN hide_values BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN email_verify_token VARCHAR(80) NULL;
ALTER TABLE users ADD COLUMN reset_token VARCHAR(80) NULL;
ALTER TABLE users ADD COLUMN reset_token_expires DATETIME NULL;
ALTER TABLE users ADD COLUMN two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN two_factor_secret VARCHAR(64) NULL;
ALTER TABLE users ADD COLUMN pin_hash VARCHAR(255) NULL;
ALTER TABLE users ADD COLUMN biometric_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN auto_lock_minutes INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN provider ENUM('local','google','apple') NOT NULL DEFAULT 'local';
ALTER TABLE users ADD COLUMN provider_id VARCHAR(120) NULL;
ALTER TABLE users ADD COLUMN plan ENUM('free','premium','family_premium') NOT NULL DEFAULT 'free';
ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN last_login_at DATETIME NULL;
ALTER TABLE users ADD COLUMN deleted_at DATETIME NULL;

CREATE INDEX idx_users_provider ON users (provider, provider_id);
CREATE INDEX idx_users_reset_token ON users (reset_token);

CREATE TABLE IF NOT EXISTS user_sessions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  token_hash CHAR(64) NOT NULL,
  device_name VARCHAR(120),
  platform VARCHAR(40),
  ip_address VARCHAR(45),
  user_agent VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_seen_at DATETIME NULL,
  expires_at DATETIME NULL,
  revoked_at DATETIME NULL,
  UNIQUE KEY unique_token (token_hash),
  KEY idx_sessions_user (user_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS access_logs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NULL,
  email VARCHAR(120),
  action ENUM('login','logout','login_failed','register','password_reset','2fa_challenge','session_revoked') NOT NULL,
  ip_address VARCHAR(45),
  user_agent VARCHAR(255),
  success BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_access_logs_user (user_id, created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NULL,
  entity VARCHAR(60) NOT NULL,
  entity_id INT NULL,
  action ENUM('create','update','delete') NOT NULL,
  changes JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_audit_entity (entity, entity_id),
  KEY idx_audit_user (user_id, created_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS notification_preferences (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  type VARCHAR(40) NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  channel_push BOOLEAN NOT NULL DEFAULT TRUE,
  channel_email BOOLEAN NOT NULL DEFAULT FALSE,
  channel_inapp BOOLEAN NOT NULL DEFAULT TRUE,
  quiet_hours_start TIME NULL,
  quiet_hours_end TIME NULL,
  UNIQUE KEY unique_pref (user_id, type),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS push_tokens (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  token VARCHAR(255) NOT NULL,
  platform ENUM('android','ios','web','windows') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_push_token (token),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
