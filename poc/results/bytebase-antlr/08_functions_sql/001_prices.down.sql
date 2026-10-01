DROP PROCEDURE auth.reset_prices(numeric);
DROP FUNCTION IF EXISTS auth.expensive_prices(numeric), auth.price_with_vat(int);
DROP TABLE auth.prices;
DROP FUNCTION auth.add_vat;
