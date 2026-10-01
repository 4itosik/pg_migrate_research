CREATE TABLE auth.users (
    id         bigserial PRIMARY KEY,
    email      text        NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth.sessions (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    bigint NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    expires_at timestamptz
);

CREATE INDEX sessions_user_id_idx ON auth.sessions (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_idx ON auth.users (lower(email));
