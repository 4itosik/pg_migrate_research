package pgschema_test

import (
	"fmt"
	"strings"

	"github.com/4itosik/pg_migrate_research/pgschema"
	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// A migration and the name of a schema go in; the migration with the schema
// inserted comes out. Nothing else changes: comments, formatting and quoting
// stay as written. Names that already have a schema are left alone.
func ExampleRewrite() {
	sql := `CREATE TABLE users (
    id    serial PRIMARY KEY,
    email text NOT NULL -- login
);
CREATE INDEX users_email_idx ON users (email);
CREATE TABLE public.audit (user_id int REFERENCES users (id));`

	out, warnings, err := pgschema.Rewrite(sql, pgschema.Options{Schema: "auth"})
	if err != nil {
		fmt.Println("error:", err)
		return
	}
	fmt.Println(out)
	fmt.Println("warnings:", len(warnings))
	// Output:
	// CREATE TABLE auth.users (
	//     id    serial PRIMARY KEY,
	//     email text NOT NULL -- login
	// );
	// CREATE INDEX users_email_idx ON auth.users (email);
	// CREATE TABLE public.audit (user_id int REFERENCES auth.users (id));
	// warnings: 0
}

// SQL that does not parse, or whose rewriting cannot be verified, is an error
// and not a text: the caller never gets SQL that was not checked.
func ExampleRewrite_error() {
	_, _, err := pgschema.Rewrite("CREATE TABLE users (id int", pgschema.Options{Schema: "auth"})
	fmt.Println("error:", err)

	_, _, err = pgschema.Rewrite("SELECT 1", pgschema.Options{Schema: "it's"}) // not a schema name that can be used
	fmt.Println("error:", err)
	// Output:
	// error: syntax error at end of input
	// error: subst: schema name "it's" has a character that is not allowed: '\''
}

// What cannot be rewritten without running the SQL is reported as a warning
// next to the text: dynamic SQL, a change of the search_path.
func ExampleRewrite_warnings() {
	sql := `DO $$ BEGIN EXECUTE 'INSERT INTO log VALUES (1)'; END $$;`
	out, warnings, err := pgschema.Rewrite(sql, pgschema.Options{Schema: "auth"})
	fmt.Println(err)
	fmt.Println(out == sql)
	for _, w := range warnings {
		fmt.Println(strings.SplitN(w, ":", 2)[0])
	}
	// Output:
	// <nil>
	// true
	// dynamic SQL (EXECUTE) inside a function body or DO block is not rewritten
}

// The settings: relations that live in another schema stay without one, and
// the uses of extensions get the schema where the extension is installed.
func ExampleRewrite_options() {
	sql := `CREATE TABLE users (
    id    uuid DEFAULT gen_random_uuid(),
    email citext,
    code  text DEFAULT encode(digest(now()::text, 'sha256'), 'hex'),
    cc    char(2) REFERENCES countries (code)
);`
	out, _, err := pgschema.Rewrite(sql, pgschema.Options{
		Schema:           "auth",
		ExcludeRelations: []string{"countries"},                                 // a table of another schema
		Extensions:       map[string]string{"citext": "ext", "pgcrypto": "ext"}, // where the extensions are installed
	})
	if err != nil {
		fmt.Println("error:", err)
		return
	}
	fmt.Println(out)
	// Output:
	// CREATE TABLE auth.users (
	//     id    uuid DEFAULT gen_random_uuid(),
	//     email ext.citext,
	//     code  text DEFAULT encode(ext.digest(now()::text, 'sha256'), 'hex'),
	//     cc    char(2) REFERENCES countries (code)
	// );
}

// Migrations that depend on each other go through one Rewriter. A type or a
// function is qualified only if some migration creates it, so every up file is
// learned before any of them is rewritten.
func ExampleRewriter() {
	files := map[string]string{
		"001_status.up.sql": "CREATE TYPE status AS ENUM ('new', 'done');",
		"002_orders.up.sql": "CREATE TABLE orders (id serial, st status DEFAULT 'new');",
		"003_more.up.sql":   "ALTER TABLE orders ADD COLUMN prev status;",
	}
	names := []string{"001_status.up.sql", "002_orders.up.sql", "003_more.up.sql"}

	rw, err := pgschema.New(pgschema.Options{Schema: "auth"})
	if err != nil {
		fmt.Println("error:", err)
		return
	}
	for _, n := range names {
		if err := rw.Learn(files[n]); err != nil {
			fmt.Println(n, "error:", err)
			return
		}
	}
	for _, n := range names {
		out, _, err := rw.Rewrite(files[n])
		if err != nil {
			fmt.Println(n, "error:", err)
			return
		}
		fmt.Println(out)
	}
	// Output:
	// CREATE TYPE auth.status AS ENUM ('new', 'done');
	// CREATE TABLE auth.orders (id serial, st auth.status DEFAULT 'new');
	// ALTER TABLE auth.orders ADD COLUMN prev auth.status;
}

// A migration rewritten once with a placeholder is a template; a service puts
// its schema in with subst.Apply, with no parser: the result is what rewriting
// with that schema gives.
func ExampleOptions_placeholder() {
	tmpl, _, err := pgschema.Rewrite("CREATE TABLE users (id serial); SELECT nextval('users_id_seq');",
		pgschema.Options{Placeholder: true})
	if err != nil {
		fmt.Println("error:", err)
		return
	}
	fmt.Println(tmpl)
	for _, schema := range []string{"auth", "my schema"} {
		sql, err := subst.Apply(tmpl, schema)
		fmt.Println(sql, err)
	}
	// Output:
	// CREATE TABLE pgschema_placeholder.users (id serial); SELECT nextval('pgschema_placeholder.users_id_seq');
	// CREATE TABLE auth.users (id serial); SELECT nextval('auth.users_id_seq'); <nil>
	// CREATE TABLE "my schema".users (id serial); SELECT nextval('"my schema".users_id_seq'); <nil>
}
