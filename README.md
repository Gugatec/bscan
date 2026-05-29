# bscan

An interactive Bash wrapper for the [Bumblebee](https://github.com/SocketDev/socket-bumblebee) malicious-package scanner. Provides a persistent configuration panel, scan profile selection, threat catalog syncing, log management, and formatted report export — all from a single terminal script.

---

## Requirements

| Dependency | Purpose |
|---|---|
| `bash` ≥ 3.2 | Script runtime (macOS system bash supported) |
| [`bumblebee`](https://github.com/SocketDev/socket-bumblebee) | The underlying scanner engine |
| `git` | Syncing bscan and threat catalog repos |
| `sudo` | Required by `bumblebee scan` |
| `jq` *(optional)* | Faster/more reliable NDJSON parsing; falls back to `awk` if absent |

---

## Installation

```bash
# 1. Clone this repo
git clone https://github.com/Gugatec/bscan.git
cd bscan

# 2. Make the script executable
chmod +x bscan.sh

# 3. (Optional) Add a convenience symlink
ln -s "$(pwd)/bscan.sh" ~/.local/bin/bscan
```

The script resolves symlinks at runtime, so it always finds its own `.env` regardless of where it is launched from.

---

## First Run

The first time `bscan.sh` is executed it detects the missing `.env` and launches an interactive **setup wizard**:

```
  ╔═══════════════════════════════════════════════════════╗
  ║           BSCAN — FIRST RUN SETUP WIZARD             ║
  ╠═══════════════════════════════════════════════════════╣
  ║  No .env found. Let's configure your environment.    ║
  ║  Required fields are marked — others have defaults.  ║
  ╚═══════════════════════════════════════════════════════╝

  [1/8] Bumblebee home directory
  Your local clone of the bumblebee GitHub repo
  > _
```

| Step | Field | Behaviour |
|---|---|---|
| 1 | Bumblebee home directory | **Required.** Re-prompts until a value is entered. |
| 2 | Scan root path | **Required.** Re-prompts until a value is entered. |
| 3 | Log directory | **Required.** Checks if the path exists and is writable; attempts `mkdir -p` if not; re-prompts on failure. |
| 4–8 | All others | Optional — press **ENTER** to accept the shown default. |

Path inputs accept shell variables (`$HOME`, `$USER`, `~`). They are expanded immediately so the stored value is always an absolute path.

On completion the wizard writes `.env` into the repo directory. This file is gitignored and stays local to your machine. To re-run the wizard at any time, delete `.env` and restart the script.

---

## Configuration

Settings are stored in `.env` (gitignored, auto-generated on first run). A safe template with placeholder values is provided in `.env-sample`.

| Variable | Default | Description |
|---|---|---|
| `BUMBLEBEE_DIR` | *(required)* | Path to your local bumblebee clone |
| `SCAN_ROOT` | *(required)* | Root directory bumblebee will scan recursively |
| `LOG_DIR` | *(required)* | Directory where report files are written |
| `OUTPUT_FORMAT` | `human` | `human` = formatted dashboard, `raw` = NDJSON passthrough |
| `EXPORT_REPORT` | `yes` | Auto-save a report file after each scan |
| `RETENTION_DAYS` | `180` | Delete report files older than this many days |
| `SYNC_BSCAN_REPO` | `yes` | Pull latest bscan script from GitHub before each run |
| `SYNC_CATALOG` | `yes` | Pull latest threat signatures from bumblebee repo before each run |
| `SCAN_MODE` | `spinner` | `spinner` = progress indicator, `verbose` = live output stream |

You can edit `.env` directly or use the **Configuration Control Panel** shown at the start of every run:

```
=========================================================
       BUMBLEBEE SCANNER CONFIGURATION CONTROL PANEL
=========================================================
  [1] Bumblebee Home Dir   : /Users/me/bumblebee
  [2] System Scan Target   : /Users
  [3] Target Output Format : human
  [4] Auto-Export Report   : yes
  [5] Log Directory Path   : /Users/me/_scripts/LOGS
  [6] Log Retention Rules  : Delete logs older than 180 days
  [7] Sync bscan Repo      : yes
  [8] Sync Threat Catalog  : yes
  [9] Scan Output Mode     : spinner
  [0] Reset to Defaults
---------------------------------------------------------
  [P] PROCEED TO RUN SCAN  |  [Q] QUIT PROGRAM
=========================================================
```

---

## Scan Profiles

| # | Profile | Description |
|---|---|---|
| 1 | `baseline` | Quick global packages/extensions checklist |
| 2 | `project` | Targeted workspace/lockfile inspection |
| 3 | `deep` *(default)* | Aggressive cross-user ecosystem sweep |
| 4 | `incident-response` | Targeted emergency vulnerability triage |

> **Note:** When `SCAN_ROOT` is set to `/` (filesystem root), a warning is shown before the confirmation prompt indicating the scan will cover the entire system and may take significantly longer.

---

## Scan Output Modes

### Spinner (default)

bumblebee runs in the background. A rotating indicator and live elapsed time are shown so you can confirm the scan is still running:

```
  [/] Scanning... 23s elapsed
```

When the scan completes the line is cleared and the report is rendered.

### Verbose

bumblebee's raw output streams live to the terminal as it runs. The output is simultaneously captured to a temp file so the formatted dashboard and report export still work normally after the scan finishes. Select via option `[9]` in the config panel or set `SCAN_MODE=verbose` in `.env`.

---

## Report Output

### Human format (default)

```
========================================================
               BUMBLEBEE SCAN REPORT
========================================================
Generated : 2026-05-29 12:00:00
Target    : /Users
Profile   : deep
Elapsed   : 42s
--------------------------------------------------------
⚠️  MALICIOUS COMPROMISES / FINDINGS DETECTED: (1 found)
--------------------------------------------------------
  • [NPM] malicious-pkg (v1.2.3) found at: /Users/me/project/node_modules

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

Passes the NDJSON stream from `bumblebee` directly to stdout. Suitable for piping into other tools.

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

Before scanning, bscan can optionally pull the latest code for:

- **bscan itself** (`SYNC_BSCAN_REPO=yes`) — ensures you always run the most recent version of this wrapper
- **Threat catalog** (`SYNC_CATALOG=yes`) — pulls fresh malicious-package signatures from the bumblebee repo

Both are enabled by default and can be toggled independently via options `[7]` and `[8]` in the config panel.

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
