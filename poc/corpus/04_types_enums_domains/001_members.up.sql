CREATE TYPE user_status AS ENUM ('active', 'blocked');
CREATE DOMAIN email_address AS text CHECK (VALUE ~ '^[^@]+@[^@]+$');
CREATE TYPE money_amount AS (amount numeric(12, 2), currency char(3));

CREATE TABLE members (
    id                int PRIMARY KEY,
    status            user_status NOT NULL DEFAULT 'active',
    email             email_address,
    balance           money_amount,
    previous_statuses user_status[] NOT NULL DEFAULT '{}'
);

ALTER TABLE members ALTER COLUMN status TYPE user_status USING status::text::user_status;
ALTER DOMAIN email_address SET NOT NULL;
COMMENT ON TYPE user_status IS 'Member status';
COMMENT ON DOMAIN email_address IS 'E-mail address';
ALTER TYPE user_status ADD VALUE IF NOT EXISTS 'deleted';
