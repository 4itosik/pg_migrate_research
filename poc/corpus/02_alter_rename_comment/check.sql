INSERT INTO auth.customers (id, title) VALUES (1, 'ACME');
INSERT INTO auth.orders (id, account_id) VALUES (1, 1);
DO $$ BEGIN
    IF obj_description('auth.customers'::regclass, 'pg_class') IS DISTINCT FROM 'Customers (renamed from accounts)' THEN
        RAISE EXCEPTION 'table comment missing';
    END IF;
END $$;
