DROP TRIGGER items_check ON auth.items;
DROP TRIGGER items_audit_trigger ON auth.items;
DROP VIEW auth.items_view;
DROP FUNCTION auth.items_view_insert(), auth.items_audit_fn(), auth.noop_trg();
DROP TABLE auth.items_audit, auth.items;
