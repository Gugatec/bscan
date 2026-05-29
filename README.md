# bscan

An interactive Bash wrapper for the [Bumblebee](https://github.com/SocketDev/bumblebee) malicious-package scanner. Provides a persistent configuration panel, profile selection, threat catalog syncing, log management, and formatted report export — all from a single terminal script.

---

## Requirements

| Dependency | Purpose |
|---|---|
| `bash` ≥ 4.0 | Script runtime |
| [`bumblebee`](https://github.com/SocketDev/bumblebee) | The underlying scanner engine |
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
ln -s "$(pwd)/bscan.sh" ~/bin/bscan
```

---

## First Run

The first time `bscan.sh` is executed it launches a **setup wizard** to collect your configuration:

```
  ╔═══════════════════════════════════════════════════════╗
  ║           BSCAN — FIRST RUN SETUP WIZARD             ║
  ╠═══════════════════════════════════════════════════════╣
  ║  No .env file found. Let's configure your settings.  ║
  ║  Press ENTER to accept the default for each value.   ║
  ╚═══════════════════════════════════════════════════════╝

  [1/8] Bumblebee home directory
  Default: ~/bumblebee
  > _
```

Pressing **ENTER** at any prompt accepts the shown default. On completion the wizard writes a `.env` file into the repo directory. This file is gitignored and stays local to your machine.

To re-run the wizard at any time, delete `.env` and restart the script.

---

## Configuration

Settings are stored in `.env` (gitignored, auto-generated on first run). A safe template with placeholder values is provided in `.env-sample`.

| Variable | Default | Description |
|---|---|---|
| `BUMBLEBEE_DIR` | `~/bumblebee` | Path to your local bumblebee clone |
| `SCAN_ROOT` | `$HOME` | Root directory to scan |
| `OUTPUT_FORMAT` | `human` | `human` = formatted dashboard, `raw` = NDJSON passthrough |
| `EXPORT_REPORT` | `yes` | Auto-save a report file after each scan |
| `LOG_DIR` | `~/_scripts/LOGS` | Directory where report files are written |
| `RETENTION_DAYS` | `180` | Delete report files older than this many days |
| `SYNC_BSCAN_REPO` | `yes` | Pull latest bscan script from GitHub before each run |
| `SYNC_CATALOG` | `yes` | Pull latest threat signatures before each run |

You can edit `.env` directly or use the **Configuration Control Panel** shown at the start of every run:

```
=========================================================
       BUMBLEBEE SCANNER CONFIGURATION CONTROL PANEL
=========================================================
  [1] Bumblebee Home Dir   : /path/to/bumblebee
  [2] System Scan Target   : /Users
  [3] Target Output Format : human
  [4] Auto-Export Report   : yes
  [5] Log Directory Path   : /Users/me/_scripts/LOGS
  [6] Log Retention Rules  : Delete logs older than 180 days
  [7] Sync bscan Repo      : yes
  [8] Sync Threat Catalog  : yes
  [9] Reset to Defaults
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

---

## Output Formats

### Human (default)

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

### Raw

Passes the NDJSON stream from `bumblebee` directly to stdout. Suitable for piping into other tools.

---

## Report Files

When `EXPORT_REPORT=yes`, a timestamped file is written to `LOG_DIR` after each scan:

```
2026_05_29_120042_bumblebee_report.txt      # human format
2026_05_29_120042_bumblebee_report.ndjson   # raw format
```

Files older than `RETENTION_DAYS` days are automatically deleted at the start of each run.

---

## Sync Behaviour

Before scanning, bscan can optionally pull the latest code for:

- **bscan itself** (`SYNC_BSCAN_REPO=yes`) — ensures you always run the most recent version of this wrapper
- **Threat catalog** (`SYNC_CATALOG=yes`) — pulls fresh malicious-package signatures from the bumblebee repo

Both are enabled by default and can be toggled independently via options `[7]` and `[8]` in the config panel, or directly in `.env`.

---

## File Structure

```
bscan/
├── bscan.sh          # Main script
├── .env              # Your local config (gitignored, auto-generated)
├── .env-sample       # Safe config template (committed)
├── .gitignore        # Excludes .env
└── README.md         # This file
```

---

## License

MIT
