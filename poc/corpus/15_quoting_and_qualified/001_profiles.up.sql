CREATE TABLE "UserProfiles" (
    "Id"          int PRIMARY KEY,
    "countryCode" char(2) REFERENCES shared.countries (code)
);
CREATE TABLE "order" (
    id         int PRIMARY KEY,
    profile_id int REFERENCES "UserProfiles" ("Id")
);
CREATE TABLE auth.already_qualified (id int);
CREATE TABLE timestamps_ref (
    id      int,
    created timestamp DEFAULT pg_catalog.now()
);

INSERT INTO "UserProfiles" SELECT 1, code FROM shared.countries WHERE code = 'RU';
INSERT INTO "order" (id, profile_id) SELECT 1, "Id" FROM "UserProfiles";
INSERT INTO auth.already_qualified VALUES (1);
COMMENT ON TABLE "order" IS 'reserved word as a table name';
