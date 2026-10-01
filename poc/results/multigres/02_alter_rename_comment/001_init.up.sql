CREATE TABLE auth.accounts (id INT PRIMARY KEY, name TEXT);
CREATE TABLE auth.orders (id INT PRIMARY KEY, account_id INT);
