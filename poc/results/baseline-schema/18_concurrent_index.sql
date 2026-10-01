CREATE SCHEMA auth;
CREATE TABLE big (
    id integer,
    v text
);
CREATE INDEX big_v_idx ON big USING btree (v);
