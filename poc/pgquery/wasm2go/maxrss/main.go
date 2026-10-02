//go:build linux

// Command maxrss is a -toolexec wrapper that reports the peak memory (RSS)
// and wall time of every compile and link step of a Go build:
//
//	go build -toolexec=/path/to/maxrss ./...
//
// Lines are appended to $MAXRSS_LOG (default: maxrss.log in the temporary
// directory), never to stderr: the go command caches what a compile step
// prints and replays it on later builds. Use -a to measure packages that are
// already in the build cache. With MAXRSS_PKG set, only compile steps of
// packages whose import path contains it are reported. Linux only: Maxrss is
// in kilobytes there.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func main() {
	cmd := exec.Command(os.Args[1], os.Args[2:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	start := time.Now()
	err := cmd.Run()
	if tool := strings.TrimSuffix(filepath.Base(os.Args[1]), ".exe"); (tool == "compile" || tool == "link") && cmd.ProcessState != nil {
		pkg := ""
		for i, a := range os.Args {
			if a == "-p" && i+1 < len(os.Args) {
				pkg = os.Args[i+1]
			}
		}
		if filter := os.Getenv("MAXRSS_PKG"); tool == "link" || pkg != "" && strings.Contains(pkg, filter) {
			log := os.Getenv("MAXRSS_LOG")
			if log == "" {
				log = filepath.Join(os.TempDir(), "maxrss.log")
			}
			var rss int64
			if ru, ok := cmd.ProcessState.SysUsage().(*syscall.Rusage); ok {
				rss = int64(ru.Maxrss) / 1024
			}
			if f, err := os.OpenFile(log, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err == nil {
				fmt.Fprintf(f, "%s %s maxrss=%dMB wall=%.1fs\n", tool, pkg, rss, time.Since(start).Seconds())
				f.Close()
			}
		}
	}
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		os.Exit(1)
	}
}
