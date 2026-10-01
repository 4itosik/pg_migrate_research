CREATE TYPE auth.priority AS ENUM ('low', 'high');
CREATE FUNCTION auth.normalize_code(code text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT lower(btrim(code)) $$;
