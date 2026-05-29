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

The setup wizard walks you through every required setting and handles all dependency installation. At step 9 it offers to install a `bscan` symlink so you can run `bscan` from anywhere in your terminal.

---

## First Run — Setup Wizard

The first time `bscan.sh` is executed it detects the missing `.env` file and launches an interactive **9-step setup wizard**:

```
  ╔═══════════════════════════════════════════════════════╗
  ║           BSCAN — FIRST RUN SETUP WIZARD             ║
  ╠═══════════════════════════════════════════════════════╣
  ║  No .env found. Let's configure your environment.    ║
  ║  Required fields are marked — others have defaults.  ║
  ╚═══════════════════════════════════════════════════════╝
```

### Path handling — applies to every path input

All path inputs in both the setup wizard and the configuration panel go through the same normalisation pipeline:

1. **Shell expansion** — `~`, `$HOME`, `$USER`, and any other shell variable are expanded immediately.
2. **Relative-path anchoring** — if the expanded result does not start with `/`, it is automatically prefixed with `$HOME/`. For example, entering `logs/bscan` becomes `/home/user/logs/bscan`. You never need to type the full absolute path.

The stored value in `.env` is always an absolute path, so the config is portable and unambiguous regardless of where bscan is launched from.

---

### Step 1 — Bumblebee home directory *(required)*

**What it asks:** The filesystem path where the bumblebee repo should live (e.g. `~/bumblebee` or just `bumblebee`).

**What it accomplishes — in order:**

#### 1a. Path normalisation
The path is normalised as described above. If the result does not already end in `/bumblebee`, the wizard appends it automatically so the directory is always named consistently.

#### 1b. Repo clone
Checks whether a valid git repository exists at the given path.

- **Found** → confirms and moves on.
- **Not found** → offers to clone `https://github.com/perplexityai/bumblebee` directly. You can confirm the default path or enter a different destination. The bumblebee repo contains the **threat catalog** (`threat_intel/`) used by every scan — it must be present.

#### 1c. Go installation check
Checks whether the `go` binary is available. Go is required to compile and install the bumblebee CLI binary.

- **Found** → moves on to 1d.
- **Not found** → offers to install Go automatically. Answering **Y** triggers the following chain:

  **1c-i. Homebrew check (if Go is missing)**
  Checks whether `brew` is available.
  - **Found** → proceeds directly to installing Go.
  - **Not found** → installs Homebrew first.

  **On Linux only**, before running the Homebrew installer, bscan installs the system packages Homebrew requires. It auto-detects the package manager and runs the appropriate command:

  | Distro family | Package manager | Packages installed |
  |---|---|---|
  | Debian / Ubuntu | `apt-get` | `build-essential procps curl file git` |
  | Fedora / RHEL 8+ | `dnf` | `Development Tools` group + `procps-ng curl file git` |
  | CentOS / RHEL 7 | `yum` | `Development Tools` group + `procps-ng curl file git` |
  | openSUSE | `zypper` | `gcc make curl file git procps` |
  | Arch Linux | `pacman` | `base-devel curl file git procps-ng` |
  | Unknown distro | — | Prints the required package names and asks you to install them manually, then re-run bscan |

  On **macOS**, Homebrew's own installer handles the only dependency (Xcode Command Line Tools) automatically — no extra step needed.

  After Homebrew is installed, bscan:
  - Detects the correct prefix (`/opt/homebrew` on Apple Silicon, `/home/linuxbrew/.linuxbrew` on Linux, `/usr/local` on Intel Mac)
  - Appends `eval "$(brew shellenv)"` to your shell rc file (`~/.zshrc` or `~/.bashrc`, detected from `$SHELL`)
  - Activates Homebrew in the current terminal session immediately

  **1c-ii. Go install via Homebrew**
  Runs `brew install go`, then:
  - Appends `export PATH="$(go env GOPATH)/bin:$PATH"` to your shell rc file
  - Exports the path in the current session so `go` is usable immediately

#### 1d. Bumblebee CLI installation check
Uses `_find_bumblebee_bin` to locate the bumblebee binary across five locations in order: system `PATH`, `$GOBIN`, `$GOPATH/bin`, `~/go/bin` (the default `go install` target), and a local build inside the repo clone.

- **Found** → confirms the path and moves on.
- **Not found** → offers to run `go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest`. If you accept:
  - Installs the binary into Go's bin directory
  - Appends that directory to your shell rc file (idempotent — skipped if already present)
  - Exports it into the current session so the binary is available immediately without opening a new terminal

> **Note:** The wizard loops back to the path prompt if the repo cannot be found or cloned — it will not proceed until bumblebee's repo is confirmed present.

---

### Step 2 — Scan root path *(required)*

**What it asks:** The root directory bumblebee will scan recursively (e.g. `/home`, `/Users`, or just `home` which becomes `$HOME/home`).

**What it accomplishes:** Normalises the path, then sets `SCAN_ROOT` in `.env`. The wizard shows a platform-appropriate example:
- macOS: `/Users` (all user home directories) or `/` (full system)
- Linux: `/home` (all user home directories) or `/` (full system)

Re-prompts until a non-empty value is entered. When `SCAN_ROOT` is set to `/`, a warning is displayed before each scan confirming the intent to scan the entire filesystem.

---

### Step 3 — Log directory *(required)*

**What it asks:** The directory where scan reports will be written (e.g. `~/logs` or just `logs`, which becomes `$HOME/logs`).

**What it accomplishes:**

1. **Path normalisation** — the path is normalised as described above. Relative paths are anchored to `$HOME` automatically.
2. **`/bscan` append prompt** — if the normalised path does not already end in `/bscan`, the wizard offers to append it, keeping all bscan reports in their own subdirectory.
3. **Directory validation** — checks whether the path exists and is writable.
4. **Auto-creation** — if the directory does not exist, attempts `mkdir -p`. Re-prompts if creation fails (e.g. permission denied).

This same flow (`_set_log_dir`) is used identically when changing the log directory from the **Configuration Control Panel** (`[5]`), so behaviour is always consistent.

---

### Step 4 — Log retention *(optional, default: 180 days)*

**What it asks:** How many days to keep report files before they are automatically purged.

**What it accomplishes:** Sets `RETENTION_DAYS`. At the start of each run, bscan deletes `.txt` and `.ndjson` report files in `LOG_DIR` that are older than this threshold.

---

### Step 5 — Output format *(optional, default: human)*

**What it asks:** Choose between `human` (formatted dashboard) or `raw` (NDJSON passthrough).

**What it accomplishes:** Sets `OUTPUT_FORMAT`.
- `human` — bscan parses the NDJSON stream and renders a structured report with findings, metrics, and an alert banner.
- `raw` — the NDJSON stream from bumblebee is passed through directly, suitable for piping into other tools.

---

### Step 6 — Auto-export report *(optional, default: yes)*

**What it asks:** Whether to automatically save a timestamped report file to `LOG_DIR` after each scan.

**What it accomplishes:** Sets `EXPORT_REPORT`. When enabled, each scan writes a file named `YYYY_MM_DD_HHmmss_bumblebee_report.txt` (human format) or `.ndjson` (raw format).

---

### Step 7 — Check for bscan updates *(optional, default: yes)*

**What it asks:** Whether to check for bscan script updates before each run.

**What it accomplishes:** Sets `SYNC_BSCAN_REPO`. When enabled, bscan fetches from its remote before each run and, if the local checkout is behind, reports how many commits and offers to `pull --ff-only`. If you accept, bscan updates itself and exits so you can re-run the latest version. The check is skipped silently if the remote is unreachable or no upstream branch exists.

---

### Step 8 — Sync threat catalog *(optional, default: yes)*

**What it asks:** Whether to pull the latest threat signatures before each scan.

**What it accomplishes:** Sets `SYNC_CATALOG`. When enabled, bscan runs `git pull` inside `BUMBLEBEE_DIR` before every scan so the exposure catalog (`threat_intel/`) stays current with the latest published malicious-package advisories.

---

### Step 9 — Install `bscan` command *(optional, default: yes)*

**What it asks:** Whether to install a `bscan` command so the script can be run from anywhere.

**What it accomplishes:** Creates a symlink `bscan → bscan.sh` in the first PATH-visible bin directory found (`~/.local/bin`, `~/bin`, or `/usr/local/bin`), falling back to `~/.local/bin` if none are in PATH yet. If the target directory is not in PATH, bscan prints the exact `export PATH=...` line to add to your shell rc file.

The script resolves symlinks at runtime, so it always finds its own `.env` and repo directory regardless of where it is launched from.

After completing step 9, the wizard saves `.env` and continues to the Configuration Control Panel.

> To re-run the wizard at any time, use option **[R] Reconfigure** in the control panel.

---

## Configuration Control Panel

Shown at the start of every run after the first. Displays all current settings and lets you change any of them before proceeding to a scan.

```
=========================================================
       BUMBLEBEE SCANNER CONFIGURATION CONTROL PANEL
=========================================================
  [1] Bumblebee Home Dir   : /home/user/bumblebee
  [2] System Scan Target   : /home
  [3] Target Output Format : human
  [4] Auto-Export Report   : yes
  [5] Log Directory Path   : /home/user/_scripts/LOGS/bscan
  [6] Log Retention Rules  : Delete logs older than 180 days
  [7] Check bscan Updates  : yes
  [8] Sync Threat Catalog  : yes
  [9] Scan Output Mode     : spinner

  [L] bscan Symlink        : /home/user/.local/bin/bscan → …/bscan.sh
  [R] Reconfigure (delete .env, re-run wizard)
  [U] Uninstall
---------------------------------------------------------
  [P] PROCEED TO RUN SCAN  |  [Q] QUIT PROGRAM
=========================================================
```

| Option | What it changes / does |
|---|---|
| `[1]` | Bumblebee repo directory (`BUMBLEBEE_DIR`) — path is normalised and `/bumblebee` is auto-appended if needed |
| `[2]` | Scan root path (`SCAN_ROOT`) — path is normalised; must already exist |
| `[3]` | Output format (`OUTPUT_FORMAT`): `human` or `raw` |
| `[4]` | Auto-export reports (`EXPORT_REPORT`): `yes` or `no` |
| `[5]` | Log directory (`LOG_DIR`) — full path flow: normalise → `/bscan` append offer → create if missing → writability check |
| `[6]` | Retention period (`RETENTION_DAYS`) in days |
| `[7]` | bscan self-update check (`SYNC_BSCAN_REPO`): `yes` or `no` |
| `[8]` | Threat catalog sync (`SYNC_CATALOG`): `yes` or `no` |
| `[9]` | Scan output mode (`SCAN_MODE`): `spinner` or `verbose` |
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

- **Step-by-step** — a `Remove? [y/N]` prompt is shown before each component. Answer `N` to skip any component you want to keep.
- **Full removal** — requires two confirmations upfront, then removes all six components automatically without further prompts.

### Components removed in order

| Step | Component | What happens |
|---|---|---|
| 1 | **bscan symlink** | Removes `bscan` from `~/.local/bin`, `~/bin`, and `/usr/local/bin` (whichever exist) |
| 2 | **bscan log folder** | Deletes `LOG_DIR` and all report files inside it |
| 3 | **Bumblebee repo** | Deletes `BUMBLEBEE_DIR` including the threat catalog |
| 4 | **Go** | Runs `brew uninstall go` (if Go was installed via Homebrew), then removes all `GOPATH/bin` and `GOPATH` lines from `~/.bashrc`, `~/.zshrc`, `~/.profile`, and `~/.bash_profile` |
| 5 | **Homebrew** | Runs the official Homebrew uninstall script, then removes all `brew shellenv` lines from the same rc files |
| 6 | **bscan itself** | Writes a small cleanup script to `/tmp/bscan_cleanup_<pid>.sh` and launches it in the background immediately after bscan exits, so the running script can cleanly delete its own repo directory |

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

bumblebee's raw NDJSON output streams live to the terminal as it runs. The output is simultaneously captured to a temp file so the formatted report and export still work normally after the scan finishes. Select via option `[9]` in the config panel or set `SCAN_MODE=verbose` in `.env`.

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

- **bscan self-update** (`SYNC_BSCAN_REPO=yes`) — fetches from the remote and, if the local checkout is behind, reports how many commits and offers to `pull --ff-only`. If accepted, bscan updates and exits so you re-run the latest version. Skipped silently when the remote is unreachable.
- **Threat catalog** (`SYNC_CATALOG=yes`) — runs `git pull` inside `BUMBLEBEE_DIR` to fetch the latest malicious-package signatures before the scan.

Both are enabled by default and toggled independently via options `[7]` and `[8]`.

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
├── bscan.sh          # Main script
├── .env              # Your local config (gitignored, auto-generated on first run)
├── .env-sample       # Safe config template (committed)
├── .gitignore        # Excludes .env
└── README.md         # This file
```

---

## License

MIT
