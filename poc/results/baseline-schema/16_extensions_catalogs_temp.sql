CREATE SCHEMA auth;
CREATE TABLE api_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_email public.citext NOT NULL,
    secret_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE table_stats (
    relname text COLLATE pg_catalog."C",
    n_live_tup bigint
);
ALTER TABLE ONLY api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);
