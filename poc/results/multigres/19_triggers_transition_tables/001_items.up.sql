CREATE TABLE auth.items (id INT PRIMARY KEY, qty INT NOT NULL);
CREATE TABLE auth.items_audit (n INT NOT NULL, at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE FUNCTION auth.items_audit_fn () RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
INSERT INTO auth.items_audit (n) SELECT COUNT(*) FROM new_rows;
RETURN NULL;
END$$;
CREATE TRIGGER items_audit_trg AFTER INSERT ON auth.items REFERENCING NEW TABLE AS new_rows EXECUTE FUNCTION auth.items_audit_fn();
CREATE VIEW auth.items_view AS SELECT id, qty FROM auth.items;
CREATE FUNCTION auth.items_view_insert () RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
INSERT INTO auth.items (id, qty) VALUES (new.id, new.qty);
RETURN new;
END$$;
CREATE TRIGGER items_view_ins INSTEAD OF INSERT ON auth.items_view FOR EACH ROW EXECUTE FUNCTION auth.items_view_insert();
CREATE FUNCTION auth.noop_trg () RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER items_check AFTER INSERT ON auth.items DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION auth.noop_trg();
ALTER TABLE auth.items DISABLE TRIGGER items_audit_trg;
ALTER TABLE auth.items ENABLE TRIGGER items_audit_trg;
ALTER TRIGGER items_audit_trg ON auth.items RENAME TO items_audit_trigger;
