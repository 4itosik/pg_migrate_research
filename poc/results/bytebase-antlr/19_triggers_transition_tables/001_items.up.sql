CREATE TABLE auth.items (
    id  int PRIMARY KEY,
    qty int NOT NULL
);
CREATE TABLE auth.items_audit (
    n  int         NOT NULL,
    at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION auth.items_audit_fn() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO auth.items_audit (n) SELECT count(*) FROM new_rows;
    RETURN NULL;
END
$$;

CREATE TRIGGER items_audit_trg
    AFTER INSERT ON auth.items
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE PROCEDURE auth.items_audit_fn();

CREATE VIEW auth.items_view AS SELECT id, qty FROM auth.items;

CREATE FUNCTION auth.items_view_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO auth.items (id, qty) VALUES (NEW.id, NEW.qty);
    RETURN NEW;
END
$$;

CREATE TRIGGER items_view_ins
    INSTEAD OF INSERT ON auth.items_view
    FOR EACH ROW EXECUTE FUNCTION auth.items_view_insert();

CREATE FUNCTION auth.noop_trg() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;

CREATE CONSTRAINT TRIGGER items_check
    AFTER INSERT ON auth.items
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION auth.noop_trg();

ALTER TABLE auth.items DISABLE TRIGGER items_audit_trg;
ALTER TABLE auth.items ENABLE TRIGGER items_audit_trg;
ALTER TRIGGER items_audit_trg ON auth.items RENAME TO items_audit_trigger;
