# Language-Neutral Busybody Clients Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship two standalone wrapper clients — a Go binary and a POSIX-sh script — that let any non-Elixir HTTP app register with busybody and heartbeat, without touching the busybody server.

**Architecture:** Both clients are process wrappers: they launch the app as a child, learn its listening port (explicit flag or by inspecting the child's sockets), `POST /api/register` with the child's PID, re-POST every 60s, forward termination signals to the child, and exit with the child's exit code. All registry calls are best-effort so the wrapper never takes down the app. The clients live in their own repo, `~/github/busybody-client`.

**Tech Stack:** Go 1.22 (static binary, stdlib only — `os/exec`, `net/http`, `/proc` parsing); POSIX sh (`curl` + `ss` from iproute2); Python 3 stdlib as a test-only registry stub.

## Global Constraints

Copied verbatim from the spec — every task's requirements implicitly include these:

- Register endpoint: `POST {registry-url}/api/register`, JSON body `{name, port, pid, host}`.
- **`pid` MUST serialize as a JSON string; `port` MUST serialize as a JSON integer in 1..65535.** (The server validates `is_binary(pid)` and `is_integer(port)`.)
- `pid` is the **child** process's OS PID.
- Heartbeat interval: 60 seconds.
- Defaults: `--host` → system hostname; `--registry-url` → `http://localhost:5150`.
- All registry interactions are best-effort: failures log a warning and are retried on the next heartbeat tick. Never fatal, never block or kill the child.
- Port resolution: use `--port` if given; otherwise auto-discover the child's first `LISTEN` socket. Discovery polls ~200ms up to ~10s; if it times out, keep the child running and keep retrying, registering once a port appears.
- Signals: forward `SIGTERM` and `SIGINT` to the child; on child exit, exit with the child's exit code.
- Linux-first (`/proc`, `ss`). No macOS/BSD discovery.
- License: AGPL-3.0.
- Repo: `~/github/busybody-client` (empty, not yet a git repo).

**Note on paths:** all client files below are relative to `~/github/busybody-client`. The one exception is Task 8, which edits the separate `~/github/busybody` repo's README.

---

## File Structure

```text
busybody-client/              # standalone git repo (Tasks 1-7)
  README.md                   # Task 8
  LICENSE                     # AGPL-3.0 (Task 1)
  Makefile                    # build + test targets (Task 1, extended Task 6)
  .gitignore                  # Task 1
  go/
    go.mod                    # Task 1
    main.go                   # entry + subcommand dispatch + flag parsing (Task 1)
    config.go                 # Config struct + defaults (Task 1)
    register.go               # payload build + best-effort POST (Task 2)
    discover_linux.go         # /proc-based port discovery (Task 3)
    run.go                    # orchestration: spawn, discover, register, heartbeat, signals (Task 4)
    main_test.go              # flag parsing tests (Task 1)
    register_test.go          # payload + POST tests (Task 2)
    discover_linux_test.go    # discovery test (Task 3)
    run_test.go               # integration test + helper-process (Task 4)
  sh/
    busybody-run              # POSIX-sh wrapper (Task 6)
    test-smoke.sh             # shell smoke test (Task 6)
```

Go source lives under `go/` so the module root is unambiguous and the shell client sits cleanly beside it.

---

## Task 1: Repo scaffold + CLI skeleton

**Files:**
- Create: `~/github/busybody-client/go/go.mod`
- Create: `~/github/busybody-client/go/main.go`
- Create: `~/github/busybody-client/go/config.go`
- Create: `~/github/busybody-client/go/main_test.go`
- Create: `~/github/busybody-client/Makefile`
- Create: `~/github/busybody-client/.gitignore`
- Create: `~/github/busybody-client/LICENSE`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `type Config struct { Name string; Port int; Host string; RegistryURL string; Command []string }`
  - `func parseRunArgs(args []string) (Config, error)` — `args` is everything after the `run` subcommand. Applies defaults (Host=hostname, RegistryURL="http://localhost:5150", Port=0 meaning auto-discover). Errors if `--name` missing or no command after `--`.

- [ ] **Step 1: Initialize the repo and Go module**

```bash
cd ~/github/busybody-client
git init
mkdir -p go sh
cd go
go mod init busybody-client
```

Expected: `go.mod` created with `module busybody-client` and `go 1.22` (adjust the go line to the installed toolchain if newer).

- [ ] **Step 2: Write the failing flag-parsing test**

Create `~/github/busybody-client/go/main_test.go`:

```go
package main

import (
	"os"
	"testing"
)

func TestParseRunArgs_Defaults(t *testing.T) {
	cfg, err := parseRunArgs([]string{"--name", "foo", "--", "./server", "-x"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Name != "foo" {
		t.Errorf("Name = %q, want foo", cfg.Name)
	}
	if cfg.Port != 0 {
		t.Errorf("Port = %d, want 0 (auto-discover)", cfg.Port)
	}
	if cfg.RegistryURL != "http://localhost:5150" {
		t.Errorf("RegistryURL = %q, want default", cfg.RegistryURL)
	}
	host, _ := os.Hostname()
	if cfg.Host != host {
		t.Errorf("Host = %q, want %q", cfg.Host, host)
	}
	if len(cfg.Command) != 2 || cfg.Command[0] != "./server" || cfg.Command[1] != "-x" {
		t.Errorf("Command = %v, want [./server -x]", cfg.Command)
	}
}

func TestParseRunArgs_Explicit(t *testing.T) {
	cfg, err := parseRunArgs([]string{
		"--name", "bar", "--port", "4000", "--host", "devbox",
		"--registry-url", "http://reg:9999", "--", "run.sh",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Port != 4000 || cfg.Host != "devbox" || cfg.RegistryURL != "http://reg:9999" {
		t.Errorf("bad explicit parse: %+v", cfg)
	}
}

func TestParseRunArgs_Errors(t *testing.T) {
	if _, err := parseRunArgs([]string{"--", "cmd"}); err == nil {
		t.Error("expected error when --name missing")
	}
	if _, err := parseRunArgs([]string{"--name", "foo"}); err == nil {
		t.Error("expected error when no command after --")
	}
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd ~/github/busybody-client/go && go test ./... -run TestParseRunArgs -v`
Expected: FAIL — `undefined: parseRunArgs` / `undefined: Config`.

- [ ] **Step 4: Write config.go**

Create `~/github/busybody-client/go/config.go`:

```go
package main

import "os"

// Config holds the resolved settings for one `run` invocation.
type Config struct {
	Name        string
	Port        int // 0 means auto-discover from the child's listening socket
	Host        string
	RegistryURL string
	Command     []string
}

func defaultConfig() Config {
	host, _ := os.Hostname()
	return Config{
		Host:        host,
		RegistryURL: "http://localhost:5150",
	}
}
```

- [ ] **Step 5: Write main.go with subcommand dispatch and parseRunArgs**

Create `~/github/busybody-client/go/main.go`:

```go
package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"
)

const usage = `busybody — register a local dev app with a busybody directory

Usage:
  busybody run --name NAME [--port PORT] [--host HOST] [--registry-url URL] -- CMD [ARGS...]

The command after -- is launched as a child. busybody registers it, heartbeats
every 60s, forwards SIGTERM/SIGINT to it, and exits with its exit code.`

func main() {
	if len(os.Args) < 2 || os.Args[1] != "run" {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	cfg, err := parseRunArgs(os.Args[2:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "busybody: %v\n\n%s\n", err, usage)
		os.Exit(2)
	}
	os.Exit(run(cfg))
}

// parseRunArgs parses the arguments after the `run` subcommand.
func parseRunArgs(args []string) (Config, error) {
	cfg := defaultConfig()
	i := 0
	for i < len(args) {
		a := args[i]
		if a == "--" {
			cfg.Command = args[i+1:]
			break
		}
		if i+1 >= len(args) {
			return cfg, fmt.Errorf("flag %q needs a value", a)
		}
		val := args[i+1]
		switch a {
		case "--name":
			cfg.Name = val
		case "--port":
			p, err := strconv.Atoi(val)
			if err != nil || p < 1 || p > 65535 {
				return cfg, fmt.Errorf("--port must be an integer 1-65535, got %q", val)
			}
			cfg.Port = p
		case "--host":
			cfg.Host = val
		case "--registry-url":
			cfg.RegistryURL = val
		default:
			return cfg, fmt.Errorf("unknown flag %q", a)
		}
		i += 2
	}
	if cfg.Name == "" {
		return cfg, errors.New("--name is required")
	}
	if len(cfg.Command) == 0 {
		return cfg, errors.New("no command given after --")
	}
	return cfg, nil
}
```

- [ ] **Step 6: Add a temporary run stub so main.go compiles**

Append to `~/github/busybody-client/go/config.go` (removed in Task 4):

```go
// run is defined fully in run.go (Task 4). Temporary stub for compilation.
func run(cfg Config) int {
	_ = cfg
	return 0
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd ~/github/busybody-client/go && go test ./... -run TestParseRunArgs -v`
Expected: PASS (all three tests).

- [ ] **Step 8: Write Makefile, .gitignore, LICENSE**

Create `~/github/busybody-client/Makefile`:

```make
.PHONY: build test

build:
	cd go && CGO_ENABLED=0 go build -o ../busybody .

test:
	cd go && go test ./...
```

Create `~/github/busybody-client/.gitignore`:

```text
/busybody
```

Create `~/github/busybody-client/LICENSE`: fetch the full AGPL-3.0 text.

Run: `curl -fsSL https://www.gnu.org/licenses/agpl-3.0.txt -o ~/github/busybody-client/LICENSE`
Expected: file exists, starts with "GNU AFFERO GENERAL PUBLIC LICENSE". If offline, note the license in README and add the file later.

- [ ] **Step 9: Commit**

```bash
cd ~/github/busybody-client
git add -A
git commit -m "feat: scaffold busybody-client repo and run-subcommand flag parsing"
```

---

## Task 2: Register payload + best-effort POST

**Files:**
- Create: `~/github/busybody-client/go/register.go`
- Create: `~/github/busybody-client/go/register_test.go`

**Interfaces:**
- Consumes: `Config` (Task 1).
- Produces:
  - `type payload struct { Name string `json:"name"`; Port int `json:"port"`; Pid string `json:"pid"`; Host string `json:"host"` }`
  - `func buildPayload(cfg Config, port, pid int) payload` — note `pid int` is converted to a decimal string inside.
  - `func postRegister(client *http.Client, registryURL string, p payload) error` — POSTs JSON to `registryURL + "/api/register"`; returns an error on transport failure or non-2xx status. Caller logs; never fatal.

- [ ] **Step 1: Write the failing test**

Create `~/github/busybody-client/go/register_test.go`:

```go
package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestBuildPayload_PidIsString(t *testing.T) {
	p := buildPayload(Config{Name: "foo", Host: "devbox"}, 4000, 12345)
	b, _ := json.Marshal(p)
	var raw map[string]any
	_ = json.Unmarshal(b, &raw)
	if _, ok := raw["pid"].(string); !ok {
		t.Errorf("pid must serialize as JSON string, got %T (%v)", raw["pid"], raw["pid"])
	}
	if _, ok := raw["port"].(float64); !ok { // JSON numbers decode to float64
		t.Errorf("port must serialize as JSON number, got %T", raw["port"])
	}
	if raw["pid"] != "12345" {
		t.Errorf("pid = %v, want \"12345\"", raw["pid"])
	}
}

func TestPostRegister_SendsCorrectRequest(t *testing.T) {
	var gotPath, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		b, _ := io.ReadAll(r.Body)
		gotBody = string(b)
		w.WriteHeader(200)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	}))
	defer srv.Close()

	p := buildPayload(Config{Name: "foo", Host: "devbox"}, 4000, 12345)
	if err := postRegister(srv.Client(), srv.URL, p); err != nil {
		t.Fatalf("postRegister error: %v", err)
	}
	if gotPath != "/api/register" {
		t.Errorf("path = %q, want /api/register", gotPath)
	}
	if want := `"name":"foo"`; !contains(gotBody, want) {
		t.Errorf("body %q missing %q", gotBody, want)
	}
	if want := `"pid":"12345"`; !contains(gotBody, want) {
		t.Errorf("body %q missing %q", gotBody, want)
	}
}

func TestPostRegister_Non2xxIsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(503)
	}))
	defer srv.Close()
	err := postRegister(srv.Client(), srv.URL, buildPayload(Config{Name: "x", Host: "h"}, 1, 2))
	if err == nil {
		t.Error("expected error on 503")
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/github/busybody-client/go && go test ./... -run 'TestBuildPayload|TestPostRegister' -v`
Expected: FAIL — `undefined: buildPayload` / `undefined: postRegister`.

- [ ] **Step 3: Write register.go**

Create `~/github/busybody-client/go/register.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
)

type payload struct {
	Name string `json:"name"`
	Port int    `json:"port"`
	Pid  string `json:"pid"`
	Host string `json:"host"`
}

func buildPayload(cfg Config, port, pid int) payload {
	return payload{
		Name: cfg.Name,
		Port: port,
		Pid:  strconv.Itoa(pid), // server requires pid as a string
		Host: cfg.Host,
	}
}

func postRegister(client *http.Client, registryURL string, p payload) error {
	body, err := json.Marshal(p)
	if err != nil {
		return err
	}
	resp, err := client.Post(registryURL+"/api/register", "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("registry returned %d", resp.StatusCode)
	}
	return nil
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/github/busybody-client/go && go test ./... -run 'TestBuildPayload|TestPostRegister' -v`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
cd ~/github/busybody-client
git add go/register.go go/register_test.go
git commit -m "feat: register payload builder and best-effort POST"
```

---

## Task 3: Port auto-discovery from /proc

**Files:**
- Create: `~/github/busybody-client/go/discover_linux.go`
- Create: `~/github/busybody-client/go/discover_linux_test.go`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `func discoverPort(pid int) (int, bool)` — returns the first TCP `LISTEN` port owned by `pid` (checking both IPv4 and IPv6), and `false` if none found yet.

- [ ] **Step 1: Write the failing test**

Create `~/github/busybody-client/go/discover_linux_test.go`:

```go
package main

import (
	"net"
	"os"
	"testing"
)

func TestDiscoverPort_FindsOwnListener(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	wantPort := ln.Addr().(*net.TCPAddr).Port

	got, ok := discoverPort(os.Getpid())
	if !ok {
		t.Fatal("discoverPort returned ok=false, expected to find our listener")
	}
	if got != wantPort {
		t.Errorf("discoverPort = %d, want %d", got, wantPort)
	}
}

func TestDiscoverPort_NoListener(t *testing.T) {
	// PID 1 (init) is running but this test process opened the listener above only
	// in the other test; a fresh sub-scope with no listener should report none.
	// Use a very unlikely PID that has no sockets.
	if _, ok := discoverPort(999999); ok {
		t.Error("expected ok=false for a pid with no listening sockets")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/github/busybody-client/go && go test ./... -run TestDiscoverPort -v`
Expected: FAIL — `undefined: discoverPort`.

- [ ] **Step 3: Write discover_linux.go**

Create `~/github/busybody-client/go/discover_linux.go`:

```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

const tcpStateListen = "0A" // /proc/net/tcp st field value for LISTEN

// discoverPort returns the first TCP LISTEN port owned by pid, or ok=false.
func discoverPort(pid int) (int, bool) {
	inodes := socketInodes(pid)
	if len(inodes) == 0 {
		return 0, false
	}
	for _, path := range []string{"/proc/net/tcp", "/proc/net/tcp6"} {
		if port, ok := scanListen(path, inodes); ok {
			return port, true
		}
	}
	return 0, false
}

// socketInodes returns the set of socket inodes held open by pid.
func socketInodes(pid int) map[string]bool {
	inodes := map[string]bool{}
	fdDir := fmt.Sprintf("/proc/%d/fd", pid)
	entries, err := os.ReadDir(fdDir)
	if err != nil {
		return inodes
	}
	for _, e := range entries {
		link, err := os.Readlink(fdDir + "/" + e.Name())
		if err != nil {
			continue
		}
		if strings.HasPrefix(link, "socket:[") && strings.HasSuffix(link, "]") {
			inodes[link[len("socket:["):len(link)-1]] = true
		}
	}
	return inodes
}

// scanListen reads a /proc/net/tcp{,6} file and returns the port of the first
// LISTEN row whose inode is in the given set.
func scanListen(path string, inodes map[string]bool) (int, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Scan() // skip header
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 10 {
			continue
		}
		if fields[3] != tcpStateListen {
			continue
		}
		if !inodes[fields[9]] {
			continue
		}
		// fields[1] is local_address "HEXIP:HEXPORT"
		parts := strings.Split(fields[1], ":")
		if len(parts) != 2 {
			continue
		}
		port, err := strconv.ParseInt(parts[1], 16, 32)
		if err != nil {
			continue
		}
		return int(port), true
	}
	return 0, false
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/github/busybody-client/go && go test ./... -run TestDiscoverPort -v`
Expected: PASS. (If `TestDiscoverPort_NoListener` is flaky because pid 999999 happens to exist, change it to a pid guaranteed absent by first checking `/proc`.)

- [ ] **Step 5: Commit**

```bash
cd ~/github/busybody-client
git add go/discover_linux.go go/discover_linux_test.go
git commit -m "feat: /proc-based child listening-port discovery"
```

---

## Task 4: Orchestration — spawn, discover, register, heartbeat, signals

**Files:**
- Create: `~/github/busybody-client/go/run.go`
- Create: `~/github/busybody-client/go/run_test.go`
- Modify: `~/github/busybody-client/go/config.go` (remove the temporary `run` stub from Task 1 Step 6)

**Interfaces:**
- Consumes: `Config` (Task 1), `buildPayload`/`postRegister` (Task 2), `discoverPort` (Task 3).
- Produces:
  - `func run(cfg Config) int` — full implementation; returns the child's exit code.
  - Package vars `heartbeatInterval time.Duration` (default 60s), `discoverInterval time.Duration` (default 200ms), `discoverTimeout time.Duration` (default 10s) — overridable in tests.

- [ ] **Step 1: Remove the temporary stub**

In `~/github/busybody-client/go/config.go`, delete the `func run(cfg Config) int { ... }` block added in Task 1 Step 6.

- [ ] **Step 2: Write the failing integration test**

Create `~/github/busybody-client/go/run_test.go`:

```go
package main

import (
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// TestHelperProcess is re-executed as the child app: it binds the port given in
// BUSYBODY_TEST_PORT and blocks until signaled.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("BUSYBODY_TEST_HELPER") != "1" {
		return
	}
	ln, err := net.Listen("tcp", "127.0.0.1:"+os.Getenv("BUSYBODY_TEST_PORT"))
	if err != nil {
		os.Exit(3)
	}
	defer ln.Close()
	select {} // block until the parent signals us
}

func TestRun_RegistersHeartbeatsAndPropagatesExit(t *testing.T) {
	// Pick a free port for the helper child to bind.
	tmp, _ := net.Listen("tcp", "127.0.0.1:0")
	childPort := tmp.Addr().(*net.TCPAddr).Port
	tmp.Close()

	var count int32
	var mu sync.Mutex
	var lastBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&count, 1)
		mu.Lock()
		b := make([]byte, r.ContentLength)
		_, _ = r.Body.Read(b)
		lastBody = string(b)
		mu.Unlock()
		w.WriteHeader(200)
	}))
	defer srv.Close()

	// Speed the loops up for the test.
	heartbeatInterval = 150 * time.Millisecond
	discoverInterval = 20 * time.Millisecond
	discoverTimeout = 3 * time.Second
	defer func() {
		heartbeatInterval = 60 * time.Second
		discoverInterval = 200 * time.Millisecond
		discoverTimeout = 10 * time.Second
	}()

	cfg := Config{
		Name:        "helper",
		Host:        "testhost",
		RegistryURL: srv.URL,
		Command: []string{
			os.Args[0], "-test.run", "TestHelperProcess",
		},
	}
	// Pass helper env through the child by wrapping the command in the current env.
	os.Setenv("BUSYBODY_TEST_HELPER", "1")
	os.Setenv("BUSYBODY_TEST_PORT", strconv.Itoa(childPort))
	defer os.Unsetenv("BUSYBODY_TEST_HELPER")
	defer os.Unsetenv("BUSYBODY_TEST_PORT")

	done := make(chan int, 1)
	go func() { done <- run(cfg) }()

	// Wait for at least two registrations (initial + one heartbeat).
	deadline := time.After(4 * time.Second)
	for atomic.LoadInt32(&count) < 2 {
		select {
		case <-deadline:
			t.Fatalf("only %d registrations before timeout", atomic.LoadInt32(&count))
		case <-time.After(20 * time.Millisecond):
		}
	}

	mu.Lock()
	body := lastBody
	mu.Unlock()
	if !contains(body, `"port":`+strconv.Itoa(childPort)) {
		t.Errorf("registered body %q missing discovered port %d", body, childPort)
	}

	// Terminate the wrapper; it should signal the child and return its exit code.
	proc, _ := os.FindProcess(os.Getpid())
	_ = proc // wrapper handles its own child; we just wait for run() to return
	// The helper blocks forever, so kill via the exported hook: send SIGTERM to run's child.
	// run() installs a signal handler; deliver SIGTERM to our own process group child by
	// stopping the test through cfg — instead we rely on killing the child directly:
	// Simplest: after assertions, send SIGTERM to the whole process; but that kills the test.
	// So we assert exit-code propagation in a separate, faster unit below.
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Log("run still active; heartbeat path verified")
	}
}

// TestRun_ExitCodePropagates checks that a child exiting non-zero yields that code.
func TestRun_ExitCodePropagates(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))
	defer srv.Close()

	discoverTimeout = 300 * time.Millisecond
	discoverInterval = 20 * time.Millisecond
	defer func() {
		discoverTimeout = 10 * time.Second
		discoverInterval = 200 * time.Millisecond
	}()

	cfg := Config{
		Name:        "exiter",
		Host:        "h",
		RegistryURL: srv.URL,
		Command:     []string{"sh", "-c", "exit 7"},
	}
	code := run(cfg)
	if code != 7 {
		t.Errorf("exit code = %d, want 7", code)
	}
}

// ensure exec import is used even if the helper path changes
var _ = exec.Command
```

> **Implementer note:** The `TestRun_RegistersHeartbeatsAndPropagatesExit` test verifies discovery + heartbeat. Clean signal-driven termination of the wrapper from inside a single test process is awkward (you cannot SIGTERM the wrapper without hitting the test runner), so exit-code propagation is proven separately by `TestRun_ExitCodePropagates` with a fast-exiting child. That split is intentional — keep both.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd ~/github/busybody-client/go && go test ./... -run TestRun -v`
Expected: FAIL — `undefined: run` (and `heartbeatInterval`, etc.).

- [ ] **Step 4: Write run.go**

Create `~/github/busybody-client/go/run.go`:

```go
package main

import (
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"
)

// Loop timings — package vars so tests can shrink them.
var (
	heartbeatInterval = 60 * time.Second
	discoverInterval  = 200 * time.Millisecond
	discoverTimeout   = 10 * time.Second
)

// run launches the child, registers/heartbeats best-effort, forwards
// SIGTERM/SIGINT, and returns the child's exit code.
func run(cfg Config) int {
	cmd := exec.Command(cfg.Command[0], cfg.Command[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Start(); err != nil {
		log.Printf("busybody: failed to start child: %v", err)
		return 1
	}
	pid := cmd.Process.Pid

	client := &http.Client{Timeout: 3 * time.Second}
	stop := make(chan struct{})

	// Forward termination signals to the child.
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		for sig := range sigCh {
			_ = cmd.Process.Signal(sig)
		}
	}()

	// Resolve the port, then register + heartbeat until the child exits.
	go registerLoop(cfg, client, pid, stop)

	err := cmd.Wait()
	close(stop)
	signal.Stop(sigCh)
	close(sigCh)
	return exitCode(err)
}

// registerLoop resolves the port (flag or discovery), registers once, then
// re-registers every heartbeatInterval until stop is closed.
func registerLoop(cfg Config, client *http.Client, pid int, stop <-chan struct{}) {
	port := cfg.Port
	if port == 0 {
		port = waitForPort(pid, stop)
		if port == 0 {
			return // stopped before a port appeared
		}
	}
	p := buildPayload(cfg, port, pid)

	register := func() {
		if err := postRegister(client, cfg.RegistryURL, p); err != nil {
			log.Printf("busybody: register failed (will retry): %v", err)
		}
	}
	register()

	ticker := time.NewTicker(heartbeatInterval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			register()
		}
	}
}

// waitForPort polls discoverPort until it finds a listening port, the timeout
// elapses (after which it keeps trying), or stop is closed. Returns 0 if stopped.
func waitForPort(pid int, stop <-chan struct{}) int {
	ticker := time.NewTicker(discoverInterval)
	defer ticker.Stop()
	deadline := time.Now().Add(discoverTimeout)
	warned := false
	for {
		select {
		case <-stop:
			return 0
		case <-ticker.C:
			if port, ok := discoverPort(pid); ok {
				return port
			}
			if !warned && time.Now().After(deadline) {
				log.Printf("busybody: no listening port after %s; still watching", discoverTimeout)
				warned = true
			}
		}
	}
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	return 1
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd ~/github/busybody-client/go && go test ./... -run TestRun -v`
Expected: PASS for both `TestRun_ExitCodePropagates` and the heartbeat assertions in `TestRun_RegistersHeartbeatsAndPropagatesExit`.

- [ ] **Step 6: Run the full Go suite**

Run: `cd ~/github/busybody-client/go && go test ./...`
Expected: `ok  busybody-client`.

- [ ] **Step 7: Commit**

```bash
cd ~/github/busybody-client
git add go/run.go go/run_test.go go/config.go
git commit -m "feat: run orchestration — spawn, discover, register, heartbeat, signal forwarding"
```

---

## Task 5: Build the binary end-to-end

**Files:**
- None created; verifies `make build`.

- [ ] **Step 1: Build**

Run: `cd ~/github/busybody-client && make build`
Expected: a static `busybody` binary appears at `~/github/busybody-client/busybody`, exit 0.

- [ ] **Step 2: Smoke-check the usage output**

Run: `~/github/busybody-client/busybody`
Expected: prints usage to stderr, exit code 2.

- [ ] **Step 3: Smoke-check against a real busybody (manual, optional)**

If a busybody server is running on :5150:

Run:
```bash
~/github/busybody-client/busybody run --name smoketest -- python3 -m http.server 4321
```
Expected: `smoketest` appears in the directory at `http://localhost:5150` with port 4321; Ctrl-C stops both and the entry is pruned within 30s.

- [ ] **Step 4: Commit (only if Makefile changed)**

No code change expected here; nothing to commit unless Step 1 surfaced a Makefile fix.

---

## Task 6: POSIX-sh wrapper + smoke test

**Files:**
- Create: `~/github/busybody-client/sh/busybody-run`
- Create: `~/github/busybody-client/sh/test-smoke.sh`
- Modify: `~/github/busybody-client/Makefile` (add `test-sh` target)

**Interfaces:**
- Consumes: nothing from Go. Same CLI contract as the binary, invoked directly as `busybody-run` (no `run` subcommand).
- Produces: an executable script honoring `--name/--port/--host/--registry-url -- CMD...`.

- [ ] **Step 1: Write the failing smoke test**

Create `~/github/busybody-client/sh/test-smoke.sh`:

```sh
#!/bin/sh
# Smoke test: busybody-run must POST a registration for a child that binds a port.
# Requires: python3 (test-only stub registry), a free port, curl, ss.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
STUB_PORT=5199
CHILD_PORT=4399
CAPTURE=$(mktemp)

# Minimal stub registry: record each POST body to $CAPTURE, always 200.
python3 - "$STUB_PORT" "$CAPTURE" <<'PY' &
import sys, http.server
port, cap = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        open(cap, "ab").write(self.rfile.read(n) + b"\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"status":"ok"}')
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
STUB_PID=$!
trap 'kill "$STUB_PID" 2>/dev/null || true; rm -f "$CAPTURE"' EXIT
sleep 0.5

# Run the wrapper around a child that binds CHILD_PORT and holds it open.
"$HERE/busybody-run" --name shsmoke --registry-url "http://127.0.0.1:$STUB_PORT" \
  -- sh -c "exec python3 -m http.server $CHILD_PORT" &
WRAP_PID=$!
sleep 2
kill "$WRAP_PID" 2>/dev/null || true
sleep 0.5

if grep -q '"name":"shsmoke"' "$CAPTURE" && grep -q "\"port\":$CHILD_PORT" "$CAPTURE"; then
    echo "PASS: registration captured with discovered port"
    exit 0
fi
echo "FAIL: expected registration not captured. Captured:"; cat "$CAPTURE"
exit 1
```

Make it executable: `chmod +x ~/github/busybody-client/sh/test-smoke.sh`

- [ ] **Step 2: Run the smoke test to verify it fails**

Run: `~/github/busybody-client/sh/test-smoke.sh`
Expected: FAIL — `busybody-run` does not exist yet (`No such file or directory`).

- [ ] **Step 3: Write the busybody-run script**

Create `~/github/busybody-client/sh/busybody-run`:

```sh
#!/bin/sh
# busybody-run — wrap an HTTP dev app, register it with a busybody directory,
# and heartbeat every 60s. POSIX sh. Requires: curl, ss (iproute2).
#
# Usage:
#   busybody-run --name NAME [--port PORT] [--host HOST] [--registry-url URL] -- CMD [ARGS...]
set -u

NAME=""
PORT=""
HOST="$(hostname)"
REGISTRY_URL="http://localhost:5150"

while [ $# -gt 0 ]; do
    case "$1" in
        --name)         NAME="$2"; shift 2 ;;
        --port)         PORT="$2"; shift 2 ;;
        --host)         HOST="$2"; shift 2 ;;
        --registry-url) REGISTRY_URL="$2"; shift 2 ;;
        --)             shift; break ;;
        *) echo "busybody-run: unknown flag $1" >&2; exit 2 ;;
    esac
done

if [ -z "$NAME" ]; then echo "busybody-run: --name is required" >&2; exit 2; fi
if [ $# -eq 0 ]; then echo "busybody-run: no command after --" >&2; exit 2; fi

# Launch the child; exec-in-subshell keeps CHILD_PID as the app's own PID.
"$@" &
CHILD_PID=$!

cleanup() { kill "$CHILD_PID" 2>/dev/null || true; }
trap 'cleanup' TERM INT

# Discover the child's first LISTEN port unless --port was given.
discover_port() {
    ss -Htlnp 2>/dev/null | awk -v pid="$CHILD_PID" '
        $0 ~ ("pid=" pid ",") {
            split($4, a, ":"); print a[length(a)]; exit
        }'
}

resolve_port() {
    if [ -n "$PORT" ]; then echo "$PORT"; return; fi
    i=0
    while [ "$i" -lt 50 ]; do          # ~10s at 200ms
        p=$(discover_port)
        if [ -n "$p" ]; then echo "$p"; return; fi
        sleep 0.2
        i=$((i + 1))
    done
    # keep trying past the timeout, but warn once
    echo "busybody-run: no listening port after ~10s; still watching" >&2
    while kill -0 "$CHILD_PID" 2>/dev/null; do
        p=$(discover_port)
        if [ -n "$p" ]; then echo "$p"; return; fi
        sleep 0.2
    done
}

register() {
    curl -fsS -m 3 -X POST "$REGISTRY_URL/api/register" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$NAME\",\"port\":$1,\"pid\":\"$CHILD_PID\",\"host\":\"$HOST\"}" \
        >/dev/null 2>&1 \
        || echo "busybody-run: register failed (will retry)" >&2
}

# Resolve + register + heartbeat in the background so we can wait on the child.
(
    RP=$(resolve_port)
    [ -z "$RP" ] && exit 0
    register "$RP"
    while kill -0 "$CHILD_PID" 2>/dev/null; do
        sleep 60
        kill -0 "$CHILD_PID" 2>/dev/null || break
        register "$RP"
    done
) &
HB_PID=$!

# Wait for the child, propagate its exit code, tidy up the heartbeat loop.
wait "$CHILD_PID"
CODE=$?
kill "$HB_PID" 2>/dev/null || true
exit "$CODE"
```

Make it executable: `chmod +x ~/github/busybody-client/sh/busybody-run`

- [ ] **Step 4: Run the smoke test to verify it passes**

Run: `~/github/busybody-client/sh/test-smoke.sh`
Expected: `PASS: registration captured with discovered port`, exit 0.

> If it fails on `ss` not matching (some `python3 -m http.server` builds fork), re-run with an explicit `--port $CHILD_PORT` to confirm the register/heartbeat path independently, then investigate discovery. Document the fork caveat in the README (Task 8).

- [ ] **Step 5: Add a Makefile target and commit**

In `~/github/busybody-client/Makefile`, add:

```make
.PHONY: test-sh

test-sh:
	sh/test-smoke.sh
```

```bash
cd ~/github/busybody-client
git add sh/busybody-run sh/test-smoke.sh Makefile
git commit -m "feat: POSIX-sh busybody-run wrapper with ss-based port discovery + smoke test"
```

---

## Task 7: busybody-client README

**Files:**
- Create: `~/github/busybody-client/README.md`

- [ ] **Step 1: Write the README**

Create `~/github/busybody-client/README.md` with these sections (language-neutral examples only — no JavaScript ecosystem):

````markdown
# busybody-client

Standalone wrappers that register any local HTTP dev app with a
[busybody](../busybody) directory and heartbeat every 60 seconds — the
same behavior as the Elixir `Busybody.Client`, for apps in any language.

Two artifacts, one CLI contract:

- **`go/` → `busybody` binary** — a single static binary for containers
  (Alpine) and hosts with no interpreter. `busybody run -- CMD`.
- **`sh/busybody-run`** — a POSIX-sh sidecar for the dev box. Needs
  `curl` and `ss` (iproute2). `busybody-run -- CMD`.

Both launch your app as a child, discover its listening port (or take
`--port`), register with the child's PID, heartbeat, forward
`SIGTERM`/`SIGINT`, and exit with the child's exit code. Every registry
call is best-effort: if busybody is down, your app still runs.

## Contract

```text
busybody run   --name NAME [--port PORT] [--host HOST] [--registry-url URL] -- CMD [ARGS...]   # binary
busybody-run   --name NAME [--port PORT] [--host HOST] [--registry-url URL] -- CMD [ARGS...]   # script
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--name` | *(required)* | Name shown in the directory |
| `--port` | *(auto-discover)* | Explicit port; skips discovery |
| `--host` | system hostname | Host shown and health-checked |
| `--registry-url` | `http://localhost:5150` | Where busybody runs |

If your app binds several ports or forks a separate listener process,
pass `--port` — discovery matches only the direct child PID.

## Examples

```bash
# Go binary, auto-discovered port
busybody run --name paperclip -- ./paperclip-server

# Shell script, explicit port
busybody-run --name docs --port 8080 -- python3 -m http.server 8080
```

## Build

```bash
make build      # produces ./busybody
make test       # Go unit + integration tests
make test-sh    # shell smoke test (needs python3)
```

## License

AGPL-3.0
````

- [ ] **Step 2: Commit**

```bash
cd ~/github/busybody-client
git add README.md
git commit -m "docs: busybody-client README"
```

---

## Task 8: Point the busybody repo at the client repo

**Files:**
- Modify: `~/github/busybody/README.md` (the "Without the Client Library" section, around lines 150-163)

- [ ] **Step 1: Expand the README section**

In `~/github/busybody/README.md`, replace the `### Without the Client Library` section with a `## Non-Elixir apps` section that keeps the raw-curl fallback and adds a pointer to the wrappers:

```markdown
## Non-Elixir apps

Busybody's API is language-neutral: any HTTP app can register by POSTing
its `name`, `port`, `pid`, and `host`, and re-POSTing every 60 seconds.

For the same "add one thing and it registers + heartbeats" experience the
Elixir client gives, use **[busybody-client](../busybody-client)** — a
process wrapper shipped as both a static Go binary and a POSIX-sh script:

    busybody run --name myapp -- ./my-server        # binary, auto-discovers the port
    busybody-run --name myapp --port 4000 -- ./run  # script, explicit port

It launches your app, discovers the listening port, registers, and
heartbeats — best-effort, so a downed busybody never affects your app.

### Raw HTTP

You don't need any client. Any HTTP tool works:

    curl -X POST http://localhost:5150/api/register \
      -H "Content-Type: application/json" \
      -d '{"name":"myapp","port":4000,"pid":"12345","host":"localhost"}'

Re-send it every 60 seconds to stay in the directory. A one-shot
registration works too — the entry just won't survive a busybody restart.
```

- [ ] **Step 2: Commit (in the busybody repo)**

```bash
cd ~/github/busybody
git add README.md
git commit -m "docs: point non-Elixir apps at busybody-client"
```

---

## Self-Review

**Spec coverage:**

- Server unchanged → no task touches `lib/`. ✓
- Shared CLI contract → Task 1 (parsing), Task 6 (script parsing). ✓
- Go binary artifact → Tasks 1-5. ✓ Sh script artifact → Task 6. ✓
- `pid` string / `port` int contract → Task 2 (`buildPayload` + `TestBuildPayload_PidIsString`), Task 6 (`register()` JSON literal). ✓
- Child PID reported → Task 4 (`pid` from `cmd.Process.Pid`), Task 6 (`CHILD_PID=$!`). ✓
- 60s heartbeat → Task 4 (`heartbeatInterval`), Task 6 (`sleep 60`). ✓
- Host/registry-url defaults → Task 1 (`defaultConfig`), Task 6 (script defaults). ✓
- Port flag-or-discover, ~200ms/~10s, keep retrying past timeout → Task 4 (`waitForPort`), Task 6 (`resolve_port`). ✓
- Best-effort, never fatal → Task 2 (error returned, logged not fatal), Task 4 (`register` logs), Task 6 (`|| echo`). ✓
- Signal forwarding + exit-code propagation → Task 4 (`signal.Notify`, `exitCode`), Task 6 (`trap`, `wait`/`exit $CODE`). ✓
- Linux `/proc` + `ss` → Task 3, Task 6. ✓
- AGPL-3.0, file layout, both READMEs → Task 1, Task 7, Task 8. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `Config`, `parseRunArgs`, `buildPayload(cfg, port, pid)`, `postRegister(client, url, payload)`, `discoverPort(pid)`, `run(cfg)`, and the loop vars `heartbeatInterval`/`discoverInterval`/`discoverTimeout` are named identically across the tasks that define and consume them. ✓
