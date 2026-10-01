INSERT INTO auth.products (id, name, price) VALUES (1, 'Pen', 1.50);
INSERT INTO auth.sales (product_id, qty) VALUES (1, 3);
REFRESH MATERIALIZED VIEW auth.product_sales_mv;
DO $$ BEGIN
    IF (SELECT total_qty FROM auth.product_sales_mv WHERE id = 1) <> 3 THEN RAISE EXCEPTION 'matview broken'; END IF;
    IF (SELECT count(*) FROM auth.visible_products) <> 1 THEN RAISE EXCEPTION 'view broken'; END IF;
END $$;
