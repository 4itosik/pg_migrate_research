CREATE TABLE roles (id int PRIMARY KEY, code text NOT NULL UNIQUE);
CREATE TABLE user_roles (
    user_id int NOT NULL,
    role_id int NOT NULL REFERENCES roles (id),
    PRIMARY KEY (user_id, role_id)
);
CREATE TABLE legacy_user_roles (user_id int, role_code text);
INSERT INTO legacy_user_roles VALUES (1, 'admin'), (2, 'viewer'), (3, 'admin'), (4, NULL);
