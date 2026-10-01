CREATE TABLE products (
    id     int PRIMARY KEY,
    name   text NOT NULL,
    price  numeric(10, 2) NOT NULL,
    active boolean NOT NULL DEFAULT true
);
CREATE TABLE sales (
    product_id int  NOT NULL REFERENCES products,
    qty        int  NOT NULL,
    sold_at    date NOT NULL DEFAULT current_date
);

CREATE VIEW active_products AS
    SELECT id, name FROM products WHERE active;

CREATE OR REPLACE VIEW product_sales AS
    SELECT p.id, p.name, sum(s.qty) AS total_qty
    FROM products p
    JOIN sales s ON s.product_id = p.id
    GROUP BY p.id, p.name;

CREATE MATERIALIZED VIEW product_sales_mv AS
    SELECT * FROM product_sales
WITH NO DATA;

CREATE UNIQUE INDEX product_sales_mv_id_idx ON product_sales_mv (id);
REFRESH MATERIALIZED VIEW product_sales_mv;
ALTER VIEW active_products RENAME TO visible_products;
