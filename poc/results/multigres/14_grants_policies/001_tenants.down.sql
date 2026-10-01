DROP POLICY IF EXISTS tenants_owner ON auth.tenants;
REVOKE ALL ON auth.tenants FROM app_reader;
REVOKE ALL ON SEQUENCE auth.tenant_seq FROM app_reader;
DROP SEQUENCE auth.tenant_seq;
DROP TABLE auth.tenants;
