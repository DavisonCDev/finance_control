CREATE DATABASE IF NOT EXISTS finance_control CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE finance_control;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(120) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS accounts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  type ENUM('checking','savings','digital','cash','investment','salary','other') DEFAULT 'checking',
  initial_balance DECIMAL(15,2) DEFAULT 0.00,
  current_balance DECIMAL(15,2) DEFAULT 0.00,
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS categories (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  name VARCHAR(60) NOT NULL,
  type ENUM('income','expense') NOT NULL,
  color VARCHAR(7) DEFAULT '#000000',
  icon VARCHAR(30) DEFAULT 'category',
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS transactions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  account_id INT,
  category_id INT,
  type ENUM('income','expense','transfer','adjustment') NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  date DATE NOT NULL,
  description VARCHAR(255),
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS credit_cards (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(120) NOT NULL,
  brand VARCHAR(30),
  limit_amount DECIMAL(15,2) DEFAULT 0.00,
  closing_day INT,
  due_day INT,
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT INTO categories (name, type, color, icon) VALUES
('Salário', 'income', '#2E7D32', 'work'),
('Freelance', 'income', '#1976D2', 'computer'),
('Investimentos', 'income', '#7B1FA2', 'trending_up'),
('Outras receitas', 'income', '#388E3C', 'add_circle'),
('Moradia', 'expense', '#D32F2F', 'home'),
('Alimentação', 'expense', '#F57C00', 'restaurant'),
('Transporte', 'expense', '#0288D1', 'directions_car'),
('Lazer', 'expense', '#C2185B', 'sports_esports'),
('Saúde', 'expense', '#00796B', 'local_hospital'),
('Educação', 'expense', '#512DA8', 'school'),
('Contas', 'expense', '#FBC02D', 'receipt'),
('Compras', 'expense', '#E64A19', 'shopping_cart'),
('Outras despesas', 'expense', '#455A64', 'more_horiz');
