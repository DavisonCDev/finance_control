-- Permite novas origens de transacao (ex.: invoice_payment = pagamento de fatura).
ALTER TABLE transactions MODIFY COLUMN source VARCHAR(40) NOT NULL DEFAULT 'manual';
