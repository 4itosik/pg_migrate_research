DROP POLICY IF EXISTS tenants_owner ON tenants;
REVOKE ALL ON tenants FROM app_reader;
REVOKE ALL ON SEQUENCE tenant_seq FROM app_reader;
DROP SEQUENCE tenant_seq;
DROP TABLE tenants;
