package parse

// Constants of the grammar chunk 08 (LOCK, DECLARE CURSOR).

// The lock modes of storage/lockdefs.h, the values of LockStmt.Mode.
const (
	NoLock                   = 0
	AccessShareLock          = 1 // SELECT
	RowShareLock             = 2 // SELECT FOR UPDATE/FOR SHARE
	RowExclusiveLock         = 3 // INSERT, UPDATE, DELETE
	ShareUpdateExclusiveLock = 4 // VACUUM (non-FULL), ANALYZE, CREATE INDEX CONCURRENTLY
	ShareLock                = 5 // CREATE INDEX (WITHOUT CONCURRENTLY)
	ShareRowExclusiveLock    = 6 // like EXCLUSIVE MODE, but allows ROW SHARE
	ExclusiveLock            = 7 // blocks ROW SHARE/SELECT...FOR UPDATE
	AccessExclusiveLock      = 8 // ALTER TABLE, DROP TABLE, VACUUM FULL, and unqualified LOCK TABLE
)

// The cursor options of nodes/parsenodes.h, the bits of
// DeclareCursorStmt.Options.
const (
	CURSOR_OPT_BINARY       = 0x0001 // BINARY
	CURSOR_OPT_SCROLL       = 0x0002 // SCROLL explicitly given
	CURSOR_OPT_NO_SCROLL    = 0x0004 // NO SCROLL explicitly given
	CURSOR_OPT_INSENSITIVE  = 0x0008 // INSENSITIVE
	CURSOR_OPT_ASENSITIVE   = 0x0010 // ASENSITIVE
	CURSOR_OPT_HOLD         = 0x0020 // WITH HOLD
	CURSOR_OPT_FAST_PLAN    = 0x0100 // prefer fast-start plan
	CURSOR_OPT_GENERIC_PLAN = 0x0200 // force use of generic plan
	CURSOR_OPT_CUSTOM_PLAN  = 0x0400 // force use of custom plan
	CURSOR_OPT_PARALLEL_OK  = 0x0800 // parallel mode OK
)
