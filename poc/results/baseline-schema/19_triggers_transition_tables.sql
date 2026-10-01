CREATE SCHEMA auth;
CREATE FUNCTION items_audit_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $BODY$;
CREATE FUNCTION items_view_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $BODY$;
CREATE FUNCTION noop_trg() RETURNS trigger
    LANGUAGE plpgsql
    AS $BODY$;
CREATE TABLE items (
    id integer NOT NULL,
    qty integer NOT NULL
);
CREATE TABLE items_audit (
    n integer NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE VIEW items_view AS
 SELECT id,
    qty
   FROM items;
ALTER TABLE ONLY items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);
CREATE TRIGGER items_audit_trigger AFTER INSERT ON items REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION items_audit_fn();
CREATE CONSTRAINT TRIGGER items_check AFTER INSERT ON items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION noop_trg();
CREATE TRIGGER items_view_ins INSTEAD OF INSERT ON items_view FOR EACH ROW EXECUTE FUNCTION items_view_insert();
