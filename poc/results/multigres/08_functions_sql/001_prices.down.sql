DROP PROCEDURE auth.reset_prices(NUMERIC);
DROP FUNCTION IF EXISTS auth.expensive_prices(NUMERIC), auth.total_with_vat();
DROP FUNCTION auth.price_with_vat(INT);
DROP TABLE auth.prices;
DROP FUNCTION auth.add_vat;
