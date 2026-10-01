CREATE TYPE auth.user_status AS ENUM ('active', 'blocked');
CREATE DOMAIN auth.email_address AS TEXT CHECK (value ~ '^[^@]+@[^@]+$');
CREATE TYPE auth.money_amount AS (amount NUMERIC(12, 2), currency bpchar(3));
CREATE TABLE auth.members (id INT PRIMARY KEY, status auth.user_status NOT NULL DEFAULT 'active', email auth.email_address, balance auth.money_amount, previous_statuses auth.user_status[] NOT NULL DEFAULT '{}');
ALTER TABLE auth.members ALTER COLUMN status TYPE auth.user_status USING CAST(CAST(status AS TEXT) AS auth.user_status);
ALTER DOMAIN auth.email_address SET NOT NULL;
COMMENT ON TYPE auth.user_status IS 'Member status';
COMMENT ON DOMAIN auth.email_address IS 'E-mail address';
ALTER TYPE auth.user_status ADD VALUE IF NOT EXISTS 'deleted';
