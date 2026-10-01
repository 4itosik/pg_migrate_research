CREATE SCHEMA auth;
CREATE TABLE products (
    id integer NOT NULL,
    name text NOT NULL,
    price numeric(10,2) NOT NULL,
    active boolean DEFAULT true NOT NULL
);
CREATE TABLE sales (
    product_id integer NOT NULL,
    qty integer NOT NULL,
    sold_at date DEFAULT CURRENT_DATE NOT NULL
);
CREATE VIEW product_sales AS
 SELECT p.id,
    p.name,
    sum(s.qty) AS total_qty
   FROM (products p
     JOIN sales s ON ((s.product_id = p.id)))
  GROUP BY p.id, p.name;
CREATE MATERIALIZED VIEW product_sales_mv AS
 SELECT id,
    name,
    total_qty
   FROM product_sales
  WITH NO DATA;
CREATE VIEW visible_products AS
 SELECT id,
    name
   FROM products
  WHERE active;
ALTER TABLE ONLY products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);
CREATE UNIQUE INDEX product_sales_mv_id_idx ON product_sales_mv USING btree (id);
ALTER TABLE ONLY sales
    ADD CONSTRAINT sales_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
