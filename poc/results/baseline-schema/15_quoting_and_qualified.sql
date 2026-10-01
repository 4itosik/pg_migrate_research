CREATE SCHEMA auth;
CREATE TABLE "UserProfiles" (
    "Id" integer NOT NULL,
    "countryCode" character(2)
);
CREATE TABLE already_qualified (
    id integer
);
CREATE TABLE "order" (
    id integer NOT NULL,
    profile_id integer
);
COMMENT ON TABLE "order" IS 'reserved word as a table name';
CREATE TABLE timestamps_ref (
    id integer,
    created timestamp without time zone DEFAULT now()
);
ALTER TABLE ONLY "UserProfiles"
    ADD CONSTRAINT "UserProfiles_pkey" PRIMARY KEY ("Id");
ALTER TABLE ONLY "order"
    ADD CONSTRAINT order_pkey PRIMARY KEY (id);
ALTER TABLE ONLY "UserProfiles"
    ADD CONSTRAINT "UserProfiles_countryCode_fkey" FOREIGN KEY ("countryCode") REFERENCES shared.countries(code);
ALTER TABLE ONLY "order"
    ADD CONSTRAINT order_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES "UserProfiles"("Id");
