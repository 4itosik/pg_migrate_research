CREATE TABLE auth."UserProfiles" ("Id" INT PRIMARY KEY, "countryCode" bpchar(2) REFERENCES shared.countries(code));
CREATE TABLE auth."order" (id INT PRIMARY KEY, profile_id INT REFERENCES auth."UserProfiles"("Id"));
CREATE TABLE auth.already_qualified (id INT);
CREATE TABLE auth.timestamps_ref (id INT, created TIMESTAMP DEFAULT pg_catalog.NOW());
INSERT INTO auth."UserProfiles" (SELECT 1, code FROM shared.countries WHERE code = 'RU');
INSERT INTO auth."order" (id, profile_id) SELECT 1, "Id" FROM auth."UserProfiles";
INSERT INTO auth.already_qualified VALUES (1);
COMMENT ON TABLE auth."order" IS 'reserved word as a table name';
