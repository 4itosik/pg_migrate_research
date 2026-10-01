-- gen_random_uuid() is built in since PostgreSQL 13; older servers take it
-- from pgcrypto, installed in public like an extension created by the DBA.
DO $$
BEGIN
    IF current_setting('server_version_num')::int < 130000 THEN
        CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA public;
    END IF;
END $$;
