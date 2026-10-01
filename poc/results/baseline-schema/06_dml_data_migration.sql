CREATE SCHEMA auth;
CREATE TABLE legacy_user_roles (
    user_id integer,
    role_code text
);
CREATE TABLE roles (
    id integer NOT NULL,
    code text NOT NULL
);
CREATE TABLE user_roles (
    user_id integer NOT NULL,
    role_id integer NOT NULL
);
ALTER TABLE ONLY roles
    ADD CONSTRAINT roles_code_key UNIQUE (code);
ALTER TABLE ONLY roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);
ALTER TABLE ONLY user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);
ALTER TABLE ONLY user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id);
