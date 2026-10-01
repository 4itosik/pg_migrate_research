CREATE TABLE auth.samples (id INT PRIMARY KEY, a INT NOT NULL, b INT NOT NULL);
CREATE STATISTICS auth.samples_ab (ndistinct, dependencies) ON a, b FROM auth.samples;
ALTER STATISTICS auth.samples_ab SET STATISTICS 200;
COMMENT ON STATISTICS auth.samples_ab IS 'a and b are correlated';
