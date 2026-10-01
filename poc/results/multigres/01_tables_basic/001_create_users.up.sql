CREATE TABLE auth.users (id bigserial PRIMARY KEY, email TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE TABLE IF NOT EXISTS auth.sessions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id BIGINT NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, expires_at TIMESTAMPTZ);
CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree ( user_id );
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_idx ON auth.users USING btree ( (lower(email)) );
