CREATE TABLE auth.accounts (id int PRIMARY KEY, name text);
CREATE TABLE auth.orders (id int PRIMARY KEY, account_id int);
