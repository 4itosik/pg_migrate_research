DROP TRIGGER items_check ON items;
DROP TRIGGER items_audit_trigger ON items;
DROP VIEW items_view;
DROP FUNCTION items_view_insert(), items_audit_fn(), noop_trg();
DROP TABLE items_audit, items;
