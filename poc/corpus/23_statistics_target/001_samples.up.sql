CREATE TABLE samples (
    id int PRIMARY KEY,
    a  int NOT NULL,
    b  int NOT NULL
);
CREATE STATISTICS samples_ab (ndistinct, dependencies) ON a, b FROM samples;
ALTER STATISTICS samples_ab SET STATISTICS 200;
COMMENT ON STATISTICS samples_ab IS 'a and b are correlated';
