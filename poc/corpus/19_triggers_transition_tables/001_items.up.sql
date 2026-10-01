CREATE TABLE items (
    id  int PRIMARY KEY,
    qty int NOT NULL
);
CREATE TABLE items_audit (
    n  int         NOT NULL,
    at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION items_audit_fn() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO items_audit (n) SELECT count(*) FROM new_rows;
    RETURN NULL;
END
$$;

CREATE TRIGGER items_audit_trg
    AFTER INSERT ON items
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
    EXECUTE PROCEDURE items_audit_fn();

CREATE VIEW items_view AS SELECT id, qty FROM items;

CREATE FUNCTION items_view_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO items (id, qty) VALUES (NEW.id, NEW.qty);
    RETURN NEW;
END
$$;

CREATE TRIGGER items_view_ins
    INSTEAD OF INSERT ON items_view
    FOR EACH ROW EXECUTE FUNCTION items_view_insert();

CREATE FUNCTION noop_trg() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$;

CREATE CONSTRAINT TRIGGER items_check
    AFTER INSERT ON items
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION noop_trg();

ALTER TABLE items DISABLE TRIGGER items_audit_trg;
ALTER TABLE items ENABLE TRIGGER items_audit_trg;
ALTER TRIGGER items_audit_trg ON items RENAME TO items_audit_trigger;
