CREATE TABLE auth.tenants (
    id    int PRIMARY KEY,
    owner name NOT NULL DEFAULT current_user
);
CREATE SEQUENCE auth.tenant_seq;

ALTER TABLE auth.tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenants_owner ON auth.tenants USING (owner = current_user);
ALTER POLICY tenants_owner ON auth.tenants USING (owner = session_user);

GRANT SELECT, INSERT ON auth.tenants TO app_reader;
GRANT USAGE, SELECT ON SEQUENCE auth.tenant_seq TO app_reader;
GRANT SELECT (id) ON TABLE auth.tenants TO app_reader;
REVOKE INSERT ON auth.tenants FROM app_reader;
COMMENT ON POLICY tenants_owner ON auth.tenants IS 'Owner only';
