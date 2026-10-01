CREATE TABLE auth."UserProfiles" (
    "Id"          int PRIMARY KEY,
    "countryCode" char(2) REFERENCES shared.countries (code)
);
CREATE TABLE auth."order" (
    id         int PRIMARY KEY,
    profile_id int REFERENCES auth."UserProfiles" ("Id")
);
CREATE TABLE auth.already_qualified (id int);
CREATE TABLE auth.timestamps_ref (
    id      int,
    created timestamp DEFAULT pg_catalog.now()
);

INSERT INTO auth."UserProfiles" SELECT 1, code FROM shared.countries WHERE code = 'RU';
INSERT INTO auth."order" (id, profile_id) SELECT 1, "Id" FROM auth."UserProfiles";
INSERT INTO auth.already_qualified VALUES (1);
COMMENT ON TABLE auth."order" IS 'reserved word as a table name';
