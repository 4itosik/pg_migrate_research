DROP PROCEDURE reset_prices(numeric);
DROP FUNCTION IF EXISTS expensive_prices(numeric), total_with_vat();
DROP FUNCTION price_with_vat(int);
DROP TABLE prices;
DROP FUNCTION add_vat;
