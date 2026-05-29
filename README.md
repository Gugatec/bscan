# bscan

An interactive Bash wrapper for the [Bumblebee](https://github.com/perplexityai/bumblebee) malicious-package scanner. Provides a fully guided first-run setup, persistent configuration panel, scan profile selection, threat catalog syncing, log management, and formatted report export — all from a single terminal script.

Compatible with **macOS** (Apple Silicon and Intel) and **Linux** (Debian, Ubuntu, Fedora, RHEL, CentOS, openSUSE, Arch).

---

## Requirements

Only three things need to exist before running bscan for the first time:

| Dependency | Purpose |
|---|---|
| `bash` ≥ 3.2 | Script runtime |
| `git` | Cloning repos and syncing the threat catalog |
| `curl` | Downloading the Homebrew installer (if needed) |

Everything else — **Homebrew**, **Go**, and the **bumblebee binary** — is detected and optionally installed automatically by the setup wizard.

| Also used at runtime | Purpose |
|---|---|
| `sudo` | Required by `bumblebee scan` to read protected paths |
| `jq` *(optional)* | Faster NDJSON parsing; falls back to `awk` if absent |

---

## Installation

### Option A — Download a release (recommended)

Download the latest `bscan.sh` from the [Releases](https://github.com/Gugatec/bscan/releases) page and install it in one step.

**macOS and Linux — one-liner:**

```bash
curl -fsSL https://github.com/Gugatec/bscan/releases/latest/download/bscan.sh -o bscan.sh
chmod +x bscan.sh
./bscan.sh
```

**Verify the download (optional but recommended):**

```bash
# Download the checksum file
curl -fsSL https://github.com/Gugatec/bscan/releases/latest/download/bscan.sh.sha256 -o bscan.sh.sha256

# Verify (macOS)
shasum -a 256 -c bscan.sh.sha256

# Verify (Linux)
sha256sum -c bscan.sh.sha256
```

### Option B — Clone from source

```bash
git clone https://github.com/Gugatec/bscan.git
cd bscan
chmod +x bscan.sh
./bscan.sh
```

The setup wizard walks through every required setting in two grouped sections — **bscan** first, then **bumblebee** — and handles all dependency installation automatically. At step 6 it offers to install a `bscan` symlink so you can run `bscan` from anywhere in your terminal.

---

## First Run — Setup Wizard

The first time `bscan.sh` is executed it detects the missing `.env` file and launches an interactive **9-step setup wizard** divided into two colour-coded sections:

```
  ╔═══════════════════════════════════════════════════════╗
  ║           BSCAN — FIRST RUN SETUP WIZARD             ║
  ╠═══════════════════════════════════════════════════════╣
  ║  No .env found. Let's configure your environment.    ║
  ║  Required fields are marked — others have defaults.  ║
  ╚═══════════════════════════════════════════════════════╝

  ╔══ BSCAN ════════════════════════════════════════════╗   (cyan)
  [1/9] …
  …
  [6/9] …

  ╔══ BUMBLEBEE ════════════════════════════════════════╗   (green)
  [7/9] …
  …
  [9/9] …
```

### Path handling — applies to every path input

All path inputs in both the setup wizard and the configuration panel go through the same normalisation pipeline:

1. **Shell expansion** — `~`, `$HOME`, `$USER`, and any other shell variable are expanded immediately.
2. **Relative-path anchoring** — if the expanded result does not start with `/`, it is automatically prefixed with `$HOME/`. For example, entering `logs/bscan` becomes `/home/user/logs/bscan`. You never need to type the full absolute path.

The stored value in `.env` is always an absolute path, so the config is portable and unambiguous regardless of where bscan is launched from.

---

## ── BSCAN section (steps 1–6) ──────────────────────────

### Step 1 — bscan auto-update

**What it asks:** Whether bscan should check for updates before each run.

**What it accomplishes:** Checks whether `$BSCAN_REPO_DIR` is a git repository.

- **Git checkout detected** → confirms auto-update is available and sets `SYNC_BSCAN_REPO=yes`.
- **Not a git repo** (e.g. installed via release download) → offers to clone the bscan repo so auto-updates become possible. If you accept, bscan clones into a temp directory and merges the `.git` folder into the existing install, preserving your `.env` and other local files. If you decline, `SYNC_BSCAN_REPO` is set to `no` automatically and the update check is skipped on every subsequent run.

---

### Step 2 — Log directory *(required)*

**What it asks:** The directory where scan reports will be written (e.g. `~/logs` or just `logs`, which becomes `$HOME/logs`).

**What it accomplishes:**

1. **Path normalisation** — relative paths are anchored to `$HOME` automatically.
2. **`/bscan` append prompt** — if the path does not already end in `/bscan`, the wizard offers to append it, keeping bscan reports in their own subdirectory.
3. **Path confirmation** — shows the final resolved path and asks for confirmation before proceeding. Answering No restarts step 2.
4. **Directory validation** — checks whether the path exists and is writable.
5. **Auto-creation** — if the directory does not exist, attempts `mkdir -p`. Re-prompts on failure.

This same flow (`_set_log_dir`) is used identically when changing the log directory from the **Configuration Control Panel** (`[2]`).

---

### Step 3 — Log retention *(optional, default: 180 days)*

**What it asks:** How many days to keep report files before they are automatically purged.

**What it accomplishes:** Sets `RETENTION_DAYS`. At the start of each run, bscan deletes `.txt` and `.ndjson` report files in `LOG_DIR` older than this threshold.

---

### Step 4 — Auto-export report *(optional, default: yes)*

**What it asks:** Whether to automatically save a timestamped report file to `LOG_DIR` after each scan.

**What it accomplishes:** Sets `EXPORT_REPORT`. When enabled, each scan writes `YYYY_MM_DD_HHmmss_bumblebee_report.txt` (human) or `.ndjson` (raw).

---

### Step 5 — Output format *(optional, default: human)*

**What it asks:** Choose between `human` (formatted dashboard) or `raw` (NDJSON passthrough).

**What it accomplishes:** Sets `OUTPUT_FORMAT`.
- `human` — bscan parses the NDJSON stream and renders a structured report with findings, metrics, and an alert banner.
- `raw` — the NDJSON stream from bumblebee is passed through directly, suitable for piping into other tools.

---

### Step 6 — Install `bscan` command *(optional, default: yes)*

**What it asks:** Whether to install a `bscan` command so the script can be run from anywhere.

**What it accomplishes:** Creates a symlink `bscan → bscan.sh` in the first PATH-visible bin directory found (`~/.local/bin`, `~/bin`, or `/usr/local/bin`), falling back to `~/.local/bin` if none are in PATH yet. If the target directory is not in PATH, bscan prints the exact `export PATH=...` line to add to your shell rc file.

The script resolves symlinks at runtime, so it always finds its own `.env` and repo directory regardless of where it is launched from.

---

## ── BUMBLEBEE section (steps 7–9) ──────────────────────

### Step 7 — Bumblebee home directory *(required)*

**What it asks:** The filesystem path where the bumblebee repo should live (e.g. `~/bumblebee` or just `bumblebee`).

**What it accomplishes — in order:**

#### 7a. Path normalisation
The path is normalised as described above. If the result does not already end in `/bumblebee`, the wizard appends it automatically.

#### 7b. Repo clone
Checks whether a valid git repository exists at the given path.

- **Found** → confirms and moves on.
- **Not found** → offers to clone `https://github.com/perplexityai/bumblebee` directly. The bumblebee repo contains the **threat catalog** (`threat_intel/`) used by every scan — it must be present.

#### 7c. Go installation check
Checks whether the `go` binary is available. Go is required to install the bumblebee CLI.

- **Found** → confirms the version and moves on to 7d. GOPATH/bin is still ensured in PATH and the shell rc file.
- **Not found** → offers to install Go automatically via Homebrew. Answering **Y** triggers:

  **Homebrew check** — checks whether `brew` is available at all known prefixes (`/opt/homebrew`, `/home/linuxbrew/.linuxbrew`, `/usr/local`).
  - **Found** → skips the installer, ensures `eval "$(brew shellenv)"` is in the shell rc and active in the current session, then proceeds to install Go.
  - **Not found** → installs Homebrew first.

  **Linux dependency pre-flight** (Linux only, before the Homebrew installer runs) — checks whether `gcc`, `make`, `curl`, `file`, `git`, and `ps` are already available. If all are present, the package manager step is skipped entirely. Otherwise bscan detects the package manager and installs only what is missing:

  | Distro family | Package manager | Packages installed |
  |---|---|---|
  | Debian / Ubuntu | `apt-get` | `build-essential procps curl file git` |
  | Fedora / RHEL 8+ | `dnf` | `Development Tools` group + `procps-ng curl file git` |
  | CentOS / RHEL 7 | `yum` | `Development Tools` group + `procps-ng curl file git` |
  | openSUSE | `zypper` | `gcc make curl file git procps` |
  | Arch Linux | `pacman` | `base-devel curl file git procps-ng` |
  | Unknown distro | — | Prints the required packages and asks you to install them manually, then re-run bscan |

  On **macOS**, Homebrew's installer handles the only dependency (Xcode Command Line Tools) automatically.

  After Homebrew is confirmed present, Go is installed via `brew install go` (skipped if `go` is already available). GOPATH/bin is then added to PATH and appended to the shell rc file.

#### 7d. Bumblebee CLI installation check
Uses `_find_bumblebee_bin` to locate the binary across: system `PATH`, `$GOBIN`, `$GOPATH/bin`, `~/go/bin`, local repo build.

- **Found** → confirms the path and moves on.
- **Not found** → offers `go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest`, appends the Go bin dir to the shell rc file, and exports it into the current session immediately.

> **Note:** The wizard loops back to the path prompt until bumblebee's repo is confirmed present.

---

### Step 8 — Scan root path *(required)*

**What it asks:** The root directory bumblebee will scan recursively (e.g. `/home`, `/Users`, or just `home` → `$HOME/home`).

**What it accomplishes:** Normalises the path, then sets `SCAN_ROOT` in `.env`. Platform-appropriate examples are shown:
- macOS: `/Users` (all user home directories) or `/` (full system)
- Linux: `/home` (all user home directories) or `/` (full system)

When `SCAN_ROOT` is `/`, a warning is displayed before each scan.

---

### Step 9 — Sync threat catalog *(optional, default: yes)*

**What it asks:** Whether to pull the latest threat signatures before each scan.

**What it accomplishes:** Sets `SYNC_CATALOG`. When enabled, bscan runs `git pull` inside `BUMBLEBEE_DIR` before every scan to keep the exposure catalog (`threat_intel/`) current.

After step 9 the wizard saves `.env` and continues to the Configuration Control Panel.

> To re-run the wizard at any time, use **[R] Reconfigure** in the control panel.

---

## Configuration Control Panel

Shown at the start of every run after the first. Settings are grouped into three colour-coded sections.

```
=========================================================
       BUMBLEBEE SCANNER CONFIGURATION CONTROL PANEL
=========================================================
── BSCAN ──────────────────────────────────────────────
  [1] Auto-Update         : yes
  [2] Log Directory       : /home/user/_scripts/LOGS/bscan
  [3] Log Retention       : Delete logs older than 180 days
  [4] Auto-Export Report  : yes
  [5] Output Format       : human
  [6] Scan Output Mode    : spinner

── BUMBLEBEE ──────────────────────────────────────────
  [7] Bumblebee Home Dir  : /home/user/bumblebee
  [8] Scan Root           : /home
  [9] Sync Threat Catalog : yes

── SYSTEM ─────────────────────────────────────────────
  [L] bscan Symlink       : /home/user/.local/bin/bscan → …
  [R] Reconfigure (delete .env, re-run wizard)
  [U] Uninstall
---------------------------------------------------------
  [P] PROCEED TO RUN SCAN  |  [Q] QUIT PROGRAM
=========================================================
```

**BSCAN section** (cyan header)

| Option | What it changes / does |
|---|---|
| `[1]` | bscan auto-update (`SYNC_BSCAN_REPO`) — runs `_ensure_bscan_repo`: detects git checkout, offers to clone if not, sets yes/no |
| `[2]` | Log directory (`LOG_DIR`) — full path flow: normalise → `/bscan` append offer → path confirmation → create if missing → writability check |
| `[3]` | Log retention (`RETENTION_DAYS`) in days |
| `[4]` | Auto-export reports (`EXPORT_REPORT`): `yes` or `no` |
| `[5]` | Output format (`OUTPUT_FORMAT`): `human` or `raw` |
| `[6]` | Scan output mode (`SCAN_MODE`): `spinner` or `verbose` |

**BUMBLEBEE section** (green header)

| Option | What it changes / does |
|---|---|
| `[7]` | Bumblebee repo directory (`BUMBLEBEE_DIR`) — path is normalised and `/bumblebee` is auto-appended if needed |
| `[8]` | Scan root path (`SCAN_ROOT`) — path is normalised; must already exist |
| `[9]` | Threat catalog sync (`SYNC_CATALOG`): `yes` or `no` |

**SYSTEM section** (yellow header)

| Option | What it does |
|---|---|
| `[L]` | Symlink management — install/recreate or remove the `bscan` command |
| `[R]` | **Reconfigure** — deletes `.env` and re-runs the full setup wizard (double-confirmed) |
| `[U]` | **Uninstall** — guided removal of any or all installed components |
| `[P]` | Proceed to scan |
| `[Q]` | Quit |

Settings are written to `.env` immediately on change. Press **ENTER** or `P` to proceed to the scan.

### Symlink management `[L]`

Shows the current symlink status (`~/.local/bin/bscan → …/bscan.sh` or `not installed`) and offers two actions:
1. **Install / recreate** — creates or replaces the symlink in the first PATH-visible bin directory
2. **Remove** — deletes the symlink from any known location it may have been placed

### Reconfigure `[R]`

Requires two separate confirmations before acting. Once confirmed, deletes `.env` and immediately re-launches the full 9-step wizard so you can start fresh with a clean configuration.

---

## Uninstall `[U]`

Accessed via option `[U]` in the Configuration Control Panel. Walks through removal of every component bscan installed, one at a time or all at once.

### Mode selection

```
  [1] Step-by-step  — confirm each component individually
  [2] Full removal  — remove everything at once
```

- **Step-by-step** — before each prompt, a dim detail line shows exactly what will be removed (symlink paths, directory path + exists status, rc files affected). Answer `N` to skip any component.
- **Full removal** — requires two confirmations upfront, then removes all six components in sequence. Go and Homebrew still require their own four-gate confirmation regardless of mode.

### Components removed in order

| Step | Component | Detail shown | Confirmation |
|---|---|---|---|
| 1 | **bscan symlink** | Lists each found symlink path, or "none found" | `Remove? [y/N]` |
| 2 | **bscan log folder** | Shows `LOG_DIR` path + exists/not-found | `Remove? [y/N]` |
| 3 | **Bumblebee repo** | Shows `BUMBLEBEE_DIR` path + exists/not-found | `Remove? [y/N]` |
| 4 | **Go** | Lists `brew uninstall go` + rc files to be cleaned | Four-gate (see below) |
| 5 | **Homebrew** | Lists uninstall script + rc files to be cleaned | Four-gate (see below) |
| 6 | **bscan itself** | Shows repo path; git deregistration runs first | `Remove? [y/N]` |

### Four-gate confirmation — Go and Homebrew

Because uninstalling Go or Homebrew is system-wide and irreversible, each requires four separate confirmations that **all default to No**:

```
  1. Are you sure you want to uninstall GO? [y/N]
  2. Confirm again — uninstall GO? [y/N]
  3. Type exactly: UNINSTALL GO
     > _
  4. ⚠  Are you sure that you want to uninstall GO?    ← bold, flashing red
        This step is not reversible.
     Final confirmation — proceed? [y/N]
```

Any wrong answer or mistyped phrase at any gate cancels the step immediately. The same four gates apply to Homebrew using the phrase `UNINSTALL HOMEBREW`.

**What each step removes:**

- **Go (step 4)** — runs `brew uninstall go` if Go is Homebrew-managed, then removes all `GOPATH/bin` and `GOPATH` lines from rc files.
- **Homebrew (step 5)** — runs the official Homebrew uninstall script, then removes all `brew shellenv` lines from rc files.

### bscan self-removal (step 6)

Before scheduling deletion, bscan removes all git remotes and deletes `.git` from the repo directory, preventing any further sync. `SYNC_BSCAN_REPO` and `SYNC_CATALOG` are set to `no` in the running session so no sync fires before exit. A cleanup script is written to `/tmp/bscan_cleanup_<pid>.sh` and launched in the background after bscan exits, cleanly deleting the repo directory.

### rc file cleanup

Steps 4 and 5 use `_remove_from_rc`, which scans the following files and removes any line containing the relevant string — leaving all other content untouched:

- `~/.bashrc`
- `~/.zshrc`
- `~/.profile`
- `~/.bash_profile`

This undoes the PATH and shell-env entries written during installation without affecting anything else in those files.

---

## Scan Profiles

After leaving the control panel, bscan prompts for a scan profile:

| # | Profile | Description |
|---|---|---|
| 1 | `baseline` | Quick inventory of global packages, editor extensions, and browser extensions |
| 2 | `project` | Targeted inspection of configured workspace directories and lockfiles |
| 3 | `deep` *(default)* | Aggressive cross-user sweep of the full `SCAN_ROOT` tree |
| 4 | `incident-response` | Emergency triage — targeted exposure check for a specific advisory |

> **Tip:** Common `SCAN_ROOT` values are `/Users` (macOS) or `/home` (Linux) to cover all user directories, or `/` to scan the entire system. When `/` is selected, bscan displays a warning before the confirmation prompt.

---

## Scan Output Modes

### Spinner (default)

bumblebee runs in the background. A rotating indicator and live elapsed time confirm the scan is still running:

```
  [/] Scanning... 23s elapsed
```

When the scan completes the indicator line is cleared and the report is rendered.

### Verbose

bumblebee's raw NDJSON output streams live to the terminal as it runs. The output is simultaneously captured to a temp file so the formatted report and export still work normally after the scan finishes. Select via option `[6]` in the config panel or set `SCAN_MODE=verbose` in `.env`.

---

## How bumblebee is found at runtime

bscan resolves the bumblebee binary path before each scan using `_find_bumblebee_bin`, which checks five locations in order:

1. System `PATH` (`command -v bumblebee`)
2. `$GOBIN/bumblebee` (explicit Go bin override)
3. `$GOPATH/bin/bumblebee` (explicit GOPATH)
4. `~/go/bin/bumblebee` (default `go install` target)
5. `$BUMBLEBEE_DIR/bumblebee` (local build inside the repo clone)

The resolved absolute path is passed directly to `sudo "$BUMBLEBEE_BIN" scan …`, so the binary is found even when sudo runs with a restricted `PATH` that strips user-local directories.

---

## Report Output

### Human format (default)

```
========================================================
               BUMBLEBEE SCAN REPORT
========================================================
Generated : 2026-05-29 12:00:00
Target    : /home
Profile   : deep
Elapsed   : 42s
--------------------------------------------------------
⚠️  MALICIOUS COMPROMISES / FINDINGS DETECTED: (1 found)
--------------------------------------------------------
  • [NPM] malicious-pkg (v1.2.3) found at: /home/user/project/node_modules

📊 SCAN PERFORMANCE METRICS:
--------------------------------------------------------
  Files Audited      : 8421
  Packages Checked   : 1204
  Engine Status      : complete
========================================================
```

If findings are detected, a red alert banner is printed after the report:

```
[!] ALERT: 1 finding(s) detected. Review the report above.
```

### Raw format

Passes the NDJSON stream from bumblebee directly to stdout. Suitable for piping into other tools or SIEM ingestion.

---

## Report Files

When `EXPORT_REPORT=yes`, a timestamped file is written to `LOG_DIR` after each scan:

```
2026_05_29_120042_bumblebee_report.txt      # human format
2026_05_29_120042_bumblebee_report.ndjson   # raw format
```

Files older than `RETENTION_DAYS` days are automatically purged at the start of each run.

---

## Sync Behaviour

Before each scan, bscan can optionally keep itself and its data current:

- **bscan self-update** (`SYNC_BSCAN_REPO=yes`) — see details below.
- **Threat catalog** (`SYNC_CATALOG=yes`) — runs `git pull` inside `BUMBLEBEE_DIR` to fetch the latest malicious-package signatures before the scan.

Both are enabled by default and toggled independently via options `[1]` (Auto-Update) and `[9]` (Sync Threat Catalog) in the control panel.

### Self-update detail

When bscan detects it is behind the remote, it offers to update:

```
==> Checking for bscan updates...
  bscan is 2 commit(s) behind origin/main.
  Update now? [Y/n]:
```

If you accept, bscan **cannot update itself while running** — overwriting the script file mid-execution would risk running half-updated code. Instead it:

1. Writes a small update script to `/tmp/bscan_update_<pid>.sh`
2. Prints an explanation of why it is exiting
3. Exits immediately
4. The background script then:
   - Stashes any local uncommitted changes (`git stash --include-untracked`) so the pull is never blocked by working-tree conflicts
   - Runs `git pull --ff-only`
   - Drops the stash
   - Prints `✔ bscan updated successfully. Re-run bscan to use the latest version.`

**Re-run bscan** once you see the success message in your terminal.

The update check is skipped silently when:
- The remote is unreachable
- There is no upstream tracking branch
- `$BSCAN_REPO_DIR` is not a git checkout (e.g. installed via release download — use menu option `[1]` to clone the repo and enable updates)

---

## Configuration Reference

Settings are stored in `.env` (gitignored, auto-generated on first run). A safe template is provided in `.env-sample`.

| Variable | Default | Description |
|---|---|---|
| `BUMBLEBEE_DIR` | *(required)* | Path to your local bumblebee clone |
| `BUMBLEBEE_REPO_URL` | `https://github.com/perplexityai/bumblebee` | Override to use an SSH URL or a fork |
| `SCAN_ROOT` | *(required)* | Root directory bumblebee will scan recursively |
| `LOG_DIR` | *(required)* | Directory where report files are written |
| `OUTPUT_FORMAT` | `human` | `human` = formatted dashboard, `raw` = NDJSON passthrough |
| `EXPORT_REPORT` | `yes` | Auto-save a report file after each scan |
| `RETENTION_DAYS` | `180` | Delete report files older than this many days |
| `SYNC_BSCAN_REPO` | `yes` | Check for bscan updates before each run |
| `SYNC_CATALOG` | `yes` | Pull latest threat signatures before each run |
| `SCAN_MODE` | `spinner` | `spinner` = progress indicator, `verbose` = live output stream |

---

## File Structure

```
bscan/
├── bscan.sh           # Main script
├── .env               # Your local config (gitignored, auto-generated on first run)
├── .env-sample        # Safe config template (committed)
├── .gitignore         # Excludes .env, bscan.sh.sha256, and local session files
└── README.md          # This file
```

> `bscan.sh.sha256` is generated at release time and uploaded as a release asset — it is gitignored and not committed to the repo.

---

## Release Notes

### v1.0.0 *(2026-05-29)*

First public release.

**Setup wizard**
- 9-step first-run wizard split into two colour-coded sections: **BSCAN** (cyan, steps 1–6) and **BUMBLEBEE** (green, steps 7–9)
- Step 1: detects whether bscan was installed via git clone or release download; offers to clone the repo to enable auto-updates
- Step 2: log directory with path normalisation, `/bscan` append prompt, path confirmation before creation, and auto-`mkdir`
- Step 6: installs `bscan` symlink into the first PATH-visible bin directory
- Step 7: full bumblebee dependency chain — Linux system package pre-flight (skipped if tools already present), Homebrew (skipped if already installed), Go (skipped if already installed), bumblebee CLI via `go install`
- All Homebrew and Go PATH entries written to `~/.zshrc` or `~/.bashrc` and activated in the current session immediately

**Configuration Control Panel**
- Three colour-coded sections: **BSCAN** (cyan, `[1]`–`[6]`), **BUMBLEBEE** (green, `[7]`–`[9]`), **SYSTEM** (yellow, `[L]` `[R]` `[U]`)
- `[L]` symlink management (install / recreate / remove)
- `[R]` Reconfigure — deletes `.env` and re-runs the full wizard (double-confirmed)
- `[U]` Uninstall wizard (see below)

**Uninstall wizard `[U]`**
- Mode selection: step-by-step (confirm each component) or full removal (double-confirmed up front)
- Each step-by-step prompt preceded by a detail line showing exactly what will be removed
- Steps 4 (Go) and 5 (Homebrew) each require four confirmations — all defaulting to No — including typing `UNINSTALL GO` / `UNINSTALL HOMEBREW` exactly and a final bold flashing-red irreversibility warning
- Step 6 (bscan itself): removes all git remotes and `.git` before scheduling deletion, preventing any further sync; cleanup script runs in background after exit

**Self-update**
- Detached update: bscan exits cleanly and a background script stashes local changes, pulls, then notifies the user to re-run — eliminates "local changes would be overwritten" pull errors
- Clear on-screen explanation shown before exit so the user knows why bscan stopped and what to do next
- `bscan.sh.sha256` and other build-generated files added to `.gitignore` to prevent working-tree conflicts on pull

**Runtime**
- bumblebee binary auto-discovered across `PATH`, `$GOBIN`, `$GOPATH/bin`, `~/go/bin`, and local repo build
- Absolute path passed to `sudo` so the binary is found even when sudo's `PATH` strips user-local directories
- `SYNC_BSCAN_REPO` update check (menu `[1]`) and `SYNC_CATALOG` catalog sync (menu `[9]`) are independent and both enabled by default

---

## License

MIT
