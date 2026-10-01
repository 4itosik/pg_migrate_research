CREATE TABLE auth.products (
    id     int PRIMARY KEY,
    name   text NOT NULL,
    price  numeric(10, 2) NOT NULL,
    active boolean NOT NULL DEFAULT true
);
CREATE TABLE auth.sales (
    product_id int  NOT NULL REFERENCES auth.products,
    qty        int  NOT NULL,
    sold_at    date NOT NULL DEFAULT current_date
);

CREATE VIEW auth.active_products AS
    SELECT id, name FROM auth.products WHERE active;

CREATE OR REPLACE VIEW auth.product_sales AS
    SELECT p.id, p.name, sum(s.qty) AS total_qty
    FROM auth.products p
    JOIN auth.sales s ON s.product_id = p.id
    GROUP BY p.id, p.name;

CREATE MATERIALIZED VIEW auth.product_sales_mv AS
    SELECT * FROM auth.product_sales
WITH NO DATA;

CREATE UNIQUE INDEX product_sales_mv_id_idx ON auth.product_sales_mv (id);
REFRESH MATERIALIZED VIEW auth.product_sales_mv;
ALTER VIEW auth.active_products RENAME TO visible_products;
