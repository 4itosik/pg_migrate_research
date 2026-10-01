CREATE TABLE auth.roles (id int PRIMARY KEY, code text NOT NULL UNIQUE);
CREATE TABLE auth.user_roles (
    user_id int NOT NULL,
    role_id int NOT NULL REFERENCES auth.roles (id),
    PRIMARY KEY (user_id, role_id)
);
CREATE TABLE auth.legacy_user_roles (user_id int, role_code text);
INSERT INTO auth.legacy_user_roles VALUES (1, 'admin'), (2, 'viewer'), (3, 'admin'), (4, NULL);
