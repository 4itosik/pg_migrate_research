CREATE SCHEMA auth;
CREATE SEQUENCE tenant_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
CREATE TABLE tenants (
    id integer NOT NULL,
    owner name DEFAULT CURRENT_USER NOT NULL
);
ALTER TABLE ONLY tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenants_owner ON tenants USING ((owner = SESSION_USER));
COMMENT ON POLICY tenants_owner ON tenants IS 'Owner only';
GRANT USAGE ON SCHEMA auth TO app_reader;
GRANT SELECT,USAGE ON SEQUENCE tenant_seq TO app_reader;
GRANT SELECT ON TABLE tenants TO app_reader;
GRANT SELECT(id) ON TABLE tenants TO app_reader;
