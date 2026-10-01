CREATE TABLE audit_log (
    id  bigserial PRIMARY KEY,
    msg text NOT NULL
);

DO $$
BEGIN
    EXECUTE 'INSERT INTO audit_log (msg) VALUES (''static string'')';
    EXECUTE format('INSERT INTO %I (msg) VALUES ($1)', 'audit_log') USING 'formatted';
END
$$;
