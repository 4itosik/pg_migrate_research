CREATE TABLE auth.roles (id INT PRIMARY KEY, code TEXT NOT NULL UNIQUE);
CREATE TABLE auth.user_roles (user_id INT NOT NULL, role_id INT NOT NULL REFERENCES auth.roles(id), PRIMARY KEY (user_id, role_id));
CREATE TABLE auth.legacy_user_roles (user_id INT, role_code TEXT);
INSERT INTO auth.legacy_user_roles VALUES (1, 'admin'), (2, 'viewer'), (3, 'admin'), (4, NULL);
