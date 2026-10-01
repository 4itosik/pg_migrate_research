CREATE SCHEMA auth;
CREATE DOMAIN email_address AS text NOT NULL
	CONSTRAINT email_address_check CHECK ((VALUE ~ '^[^@]+@[^@]+$'::text));
COMMENT ON DOMAIN email_address IS 'E-mail address';
CREATE TYPE money_amount AS (
	amount numeric(12,2),
	currency character(3)
);
CREATE TYPE user_status AS ENUM (
    'active',
    'blocked',
    'deleted'
);
COMMENT ON TYPE user_status IS 'Member status';
CREATE TABLE members (
    id integer NOT NULL,
    status user_status DEFAULT 'active'::user_status NOT NULL,
    email email_address,
    balance money_amount,
    previous_statuses user_status[] DEFAULT '{}'::user_status[] NOT NULL
);
ALTER TABLE ONLY members
    ADD CONSTRAINT members_pkey PRIMARY KEY (id);
