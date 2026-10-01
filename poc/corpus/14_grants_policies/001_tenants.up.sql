CREATE TABLE tenants (
    id    int PRIMARY KEY,
    owner name NOT NULL DEFAULT current_user
);
CREATE SEQUENCE tenant_seq;

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenants_owner ON tenants USING (owner = current_user);
ALTER POLICY tenants_owner ON tenants USING (owner = session_user);

GRANT SELECT, INSERT ON tenants TO app_reader;
GRANT USAGE, SELECT ON SEQUENCE tenant_seq TO app_reader;
GRANT SELECT (id) ON TABLE tenants TO app_reader;
REVOKE INSERT ON tenants FROM app_reader;
COMMENT ON POLICY tenants_owner ON tenants IS 'Owner only';
