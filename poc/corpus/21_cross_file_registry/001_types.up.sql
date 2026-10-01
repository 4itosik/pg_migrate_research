CREATE TYPE priority AS ENUM ('low', 'high');
CREATE FUNCTION normalize_code(code text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT lower(btrim(code)) $$;
