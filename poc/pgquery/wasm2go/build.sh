#!/usr/bin/env bash
# Regenerates ../internal/libpgquery: libpg_query (the C sources vendored in
# github.com/wasilibs/go-pgquery, the version pinned in ../go.mod) compiled to
# WebAssembly and translated to Go by wasm2go. The result is plain Go: no
# WebAssembly runtime, no cgo, nothing compiled at run time.
#
#   ./build.sh                      # downloads wasi-sdk and binaryen to $TOOLS_DIR
#   WASI_SDK=/opt/wasi-sdk BINARYEN=/opt/binaryen ./build.sh
#
# Differences from the WebAssembly build of go-pgquery:
#   - no threads (wasm32-wasip1 instead of wasm32-wasip1-threads);
#   - setjmp/longjmp are lowered Emscripten-style instead of with Wasm
#     exception handling: wasm2go turns longjmp into a Go panic that the
#     invoke_* wrappers recover;
#   - only parse, scan and PL/pgSQL parse are exported;
#   - the grammar actions of base_yyparse are split into 16 functions
#     (split_gram.py) and wasm-opt runs with -g, which keeps function
#     boundaries instead of inlining everything into a few 20k-line
#     functions. The Go compiler needs memory superlinear in function size:
#     this takes the package from 2.8 GB to 1.3 GB.
#
# Needs curl, python3 and Go; wasm2go itself needs Go 1.26, which the go
# command downloads with GOTOOLCHAIN=auto. The output is deterministic.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$here/../internal/libpgquery
wasm2go=github.com/ncruces/wasm2go@v0.4.16
tools=${TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pgquery-wasm2go}

if [ -z "${WASI_SDK:-}" ] || [ -z "${BINARYEN:-}" ]; then
	case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) w=x86_64-linux b=x86_64-linux ;;
	Linux-aarch64) w=arm64-linux b=aarch64-linux ;;
	Darwin-x86_64) w=x86_64-macos b=x86_64-macos ;;
	Darwin-arm64) w=arm64-macos b=arm64-macos ;;
	*) echo "set WASI_SDK and BINARYEN" >&2; exit 1 ;;
	esac
	if [ ! -x "$tools/wasi-sdk/bin/clang" ]; then
		mkdir -p "$tools/wasi-sdk"
		curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-34/wasi-sdk-34.0-$w.tar.gz" |
			tar xz --strip-components=1 -C "$tools/wasi-sdk"
	fi
	if [ ! -x "$tools/binaryen/bin/wasm-opt" ]; then
		mkdir -p "$tools/binaryen"
		curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_133/binaryen-version_133-$b.tar.gz" |
			tar xz --strip-components=1 -C "$tools/binaryen"
	fi
	WASI_SDK=${WASI_SDK:-$tools/wasi-sdk}
	BINARYEN=${BINARYEN:-$tools/binaryen}
fi

pgq=$(cd "$here/.." && go mod download github.com/wasilibs/go-pgquery &&
	go list -m -f '{{.Dir}}' github.com/wasilibs/go-pgquery)
(cd "$here/.." && go mod download "$wasm2go")
w2g=$(go env GOMODCACHE)/$wasm2go

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" "$work/inc" "$work/obj"
cp -r "$pgq/internal/cparser/." "$work/src/"
chmod -R u+w "$work/src"
(cd "$work/src" && patch -s -p3 <"$pgq/buildtools/wasm/patch.txt") # sigsetjmp -> setjmp

cat >"$work/inc/setjmp.h" <<'EOF'
#ifndef _SETJMP_H
#define _SETJMP_H
#include <stdint.h>
typedef struct jmp_buf_impl { void *func_invocation_id; uint32_t label; } jmp_buf[1];
typedef jmp_buf sigjmp_buf;
__attribute__((returns_twice)) int setjmp(jmp_buf);
__attribute__((noreturn)) void longjmp(jmp_buf, int);
#define sigsetjmp(env, savemask) setjmp(env)
#define siglongjmp(env, val) longjmp(env, val)
#endif
EOF
sed 's/_Thread_local //' "$w2g/libc-gen/c/setjmp_em.c" >"$work/src/zz_setjmp_em.c"
python3 "$here/split_gram.py" "$work/src/src_backend_parser_gram.c" "$work/gram.c" 16
mv "$work/gram.c" "$work/src/src_backend_parser_gram.c"

cflags=(--target=wasm32-wasip1 "--sysroot=$WASI_SDK/share/wasi-sysroot" -mllvm -enable-emscripten-sjlj -O2
	-D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL
	-DPLATFORM_DEFAULT_WAL_SYNC_METHOD=WAL_SYNC_METHOD_OPEN_DSYNC
	"-I$work/inc" "-I$work/src/include" "-I$work/src/include/postgres" -std=gnu99 -w
	"-ffile-prefix-map=$work/src/=")
for c in "$work"/src/*.c; do
	printf '%s\0' "$c"
done | xargs -0 -P"$(getconf _NPROCESSORS_ONLN)" -I{} sh -c \
	'"$0" "$@" -c "{}" -o "'"$work"'/obj/$(basename "{}").o"' "$WASI_SDK/bin/clang" "${cflags[@]}"

exports=()
for e in malloc free pg_query_init \
	pg_query_parse_protobuf pg_query_free_protobuf_parse_result \
	pg_query_scan pg_query_free_scan_result \
	pg_query_parse_plpgsql pg_query_free_plpgsql_parse_result __stack_pointer; do
	exports+=("-Wl,--export=$e")
done
"$WASI_SDK/bin/clang" --target=wasm32-wasip1 "--sysroot=$WASI_SDK/share/wasi-sysroot" -mexec-model=reactor \
	-o "$work/noopt.wasm" "$work"/obj/*.o \
	-lwasi-emulated-process-clocks -lwasi-emulated-mman -lwasi-emulated-signal \
	-Wl,--allow-undefined -Wl,--export-table -Wl,-z,stack-size=1048576 -Wl,--gc-sections "${exports[@]}"
"$BINARYEN/bin/wasm-opt" -O3 -g --no-inline='*_reduce_*' -o "$work/libpg_query.wasm" "$work/noopt.wasm"

# Run the generators outside this module: they need Go 1.26.
(
	cd "$work"
	go run "github.com/ncruces/wasm2go/libc-gen@${wasm2go#*@}" -pkg libpgquery -wasm libpg_query.wasm -o libc.go
	go run "$wasm2go" -unsafe -tags wasm2go -pkg libpgquery -provided libc.go -o libpg_query.go libpg_query.wasm
	# libc-gen has no -tags flag.
	sed -i.bak '1a\
\
//go:build wasm2go' libc.go
)
cp "$work/libpg_query.go" "$work/libc.go" "$out/"
ls -l "$out"
