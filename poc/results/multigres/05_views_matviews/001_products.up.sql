CREATE TABLE auth.products (id INT PRIMARY KEY, name TEXT NOT NULL, price NUMERIC(10, 2) NOT NULL, active BOOLEAN NOT NULL DEFAULT TRUE);
CREATE TABLE auth.sales (product_id INT NOT NULL REFERENCES auth.products, qty INT NOT NULL, sold_at DATE NOT NULL DEFAULT CURRENT_DATE);
CREATE VIEW auth.active_products AS SELECT id, name FROM auth.products WHERE active;
CREATE OR REPLACE VIEW auth.product_sales AS SELECT p.id, p.name, SUM(s.qty) AS total_qty FROM auth.products AS p INNER JOIN auth.sales AS s ON s.product_id = p.id GROUP BY p.id, p.name;
CREATE MATERIALIZED VIEW auth.product_sales_mv AS SELECT * FROM auth.product_sales WITH NO DATA;
CREATE UNIQUE INDEX product_sales_mv_id_idx ON auth.product_sales_mv USING btree ( id );
REFRESH MATERIALIZED VIEW auth.product_sales_mv;
ALTER VIEW auth.active_products RENAME TO visible_products;
