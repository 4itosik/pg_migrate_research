CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE api_keys (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_email citext NOT NULL,
    secret_hash text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO api_keys (owner_email, secret_hash)
VALUES ('Admin@Example.com', crypt('secret', gen_salt('bf', 4)));

CREATE TABLE table_stats AS
    SELECT relname::text AS relname, n_live_tup
    FROM pg_stat_user_tables
    WHERE false;

SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'auth';
SELECT table_name FROM information_schema.tables WHERE table_name = 'api_keys';

CREATE TEMP TABLE tmp_keys AS SELECT id FROM api_keys;
INSERT INTO table_stats (relname, n_live_tup) SELECT 'api_keys', count(*) FROM tmp_keys;
DROP TABLE tmp_keys;

SELECT * INTO TEMP TABLE tmp_keys2 FROM api_keys;
DROP TABLE tmp_keys2;
