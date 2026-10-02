package parse

import "math"

// fetchAll is FETCH_ALL of parsenodes.h: LONG_MAX, the howMany of FETCH ALL.
// It is the value libpg_query reports, which is built for a 32-bit target
// (WebAssembly), where long is 32 bits; a 64-bit server stores 2^63-1. The
// value does not matter for rewriting (see docs/differences.md).
const fetchAll = math.MaxInt32
