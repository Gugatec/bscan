#!/usr/bin/env bash

set -euo pipefail

# --- ANSI Color Palette ---
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# --- Error trap ---
trap 'echo -e "\n${RED}[ERROR]${RESET} Script failed at line $LINENO. Exit code: $?" >&2' ERR
trap 'rm -f "${SCAN_TMPFILE:-}"' EXIT

# --- Resolve repo dir even when launched via symlink ---
_REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
BSCAN_REPO_DIR="$(cd "$(dirname "$_REAL_SCRIPT")" && pwd)"
ENV_FILE="$BSCAN_REPO_DIR/.env"
ENV_SAMPLE="$BSCAN_REPO_DIR/.env-sample"

# --- Upstream bumblebee repo (override via BUMBLEBEE_REPO_URL in .env) ---
BUMBLEBEE_REPO_URL="${BUMBLEBEE_REPO_URL:-https://github.com/perplexityai/bumblebee}"

# --- Default values ---
DEFAULT_BUMBLEBEE_DIR="$HOME/bumblebee"
DEFAULT_SCAN_ROOT="$HOME"
DEFAULT_OUTPUT_FORMAT="human"
DEFAULT_EXPORT_REPORT="yes"
DEFAULT_LOG_DIR="$HOME/_scripts/LOGS"
DEFAULT_RETENTION_DAYS="180"
DEFAULT_SYNC_BSCAN_REPO="yes"
DEFAULT_SYNC_CATALOG="yes"
DEFAULT_SCAN_MODE="spinner"

# ---------------------------------------------------------------------------
# Config I/O
# ---------------------------------------------------------------------------

load_config() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$ENV_FILE"
    fi
    BUMBLEBEE_DIR="${BUMBLEBEE_DIR:-$DEFAULT_BUMBLEBEE_DIR}"
    SCAN_ROOT="${SCAN_ROOT:-$DEFAULT_SCAN_ROOT}"
    OUTPUT_FORMAT="${OUTPUT_FORMAT:-$DEFAULT_OUTPUT_FORMAT}"
    EXPORT_REPORT="${EXPORT_REPORT:-$DEFAULT_EXPORT_REPORT}"
    LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
    RETENTION_DAYS="${RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"
    SYNC_BSCAN_REPO="${SYNC_BSCAN_REPO:-$DEFAULT_SYNC_BSCAN_REPO}"
    SYNC_CATALOG="${SYNC_CATALOG:-$DEFAULT_SYNC_CATALOG}"
    SCAN_MODE="${SCAN_MODE:-$DEFAULT_SCAN_MODE}"
}

save_config() {
    cat > "$ENV_FILE" << EOF
# bscan local configuration — DO NOT COMMIT this file
BUMBLEBEE_DIR="$BUMBLEBEE_DIR"
BUMBLEBEE_REPO_URL="$BUMBLEBEE_REPO_URL"
SCAN_ROOT="$SCAN_ROOT"
OUTPUT_FORMAT="$OUTPUT_FORMAT"
EXPORT_REPORT="$EXPORT_REPORT"
LOG_DIR="$LOG_DIR"
RETENTION_DAYS="$RETENTION_DAYS"
SYNC_BSCAN_REPO="$SYNC_BSCAN_REPO"
SYNC_CATALOG="$SYNC_CATALOG"
SCAN_MODE="$SCAN_MODE"
EOF
}

reset_config() {
    BUMBLEBEE_DIR="$DEFAULT_BUMBLEBEE_DIR"
    SCAN_ROOT="$DEFAULT_SCAN_ROOT"
    OUTPUT_FORMAT="$DEFAULT_OUTPUT_FORMAT"
    EXPORT_REPORT="$DEFAULT_EXPORT_REPORT"
    LOG_DIR="$DEFAULT_LOG_DIR"
    RETENTION_DAYS="$DEFAULT_RETENTION_DAYS"
    SYNC_BSCAN_REPO="$DEFAULT_SYNC_BSCAN_REPO"
    SYNC_CATALOG="$DEFAULT_SYNC_CATALOG"
    SCAN_MODE="$DEFAULT_SCAN_MODE"
    save_config
    echo -e "${GREEN}Configuration reset to defaults.${RESET}"
    sleep 1
}

# ---------------------------------------------------------------------------
# First-run setup wizard
# ---------------------------------------------------------------------------

_expand_path() {
    # Expand $VAR and ~ so user-typed paths like $HOME/foo work immediately
    eval echo "$1"
}

_ensure_bumblebee() {
    echo -e "  ${CYAN}Checking Bumblebee repo at: ${BOLD}$BUMBLEBEE_DIR${RESET}"

    if [[ -d "$BUMBLEBEE_DIR" ]] && git -C "$BUMBLEBEE_DIR" rev-parse --git-dir &>/dev/null; then
        echo -e "  ${GREEN}✔ Bumblebee repo found.${RESET}"
    else
        echo -e "  ${YELLOW}Bumblebee repo not found at: $BUMBLEBEE_DIR${RESET}"
        echo ""
        read -rp "  Clone it now? [Y/n]: " _clone_yn
        _clone_yn=$(echo "${_clone_yn:-y}" | tr '[:upper:]' '[:lower:]')

        if [[ "$_clone_yn" == "y" || "$_clone_yn" == "yes" ]]; then
            echo -e "  ${DIM}Install location [default: $BUMBLEBEE_DIR — press ENTER to confirm]:${RESET}"
            read -re -p "  > " _clone_dest
            if [[ -n "$_clone_dest" ]]; then
                BUMBLEBEE_DIR=$(_expand_path "$_clone_dest")
            fi

            echo ""
            echo -e "  ${CYAN}Cloning $BUMBLEBEE_REPO_URL${RESET}"
            echo -e "  ${CYAN}        into $BUMBLEBEE_DIR ...${RESET}"
            if git clone "$BUMBLEBEE_REPO_URL" "$BUMBLEBEE_DIR"; then
                echo -e "  ${GREEN}✔ Bumblebee cloned to: $BUMBLEBEE_DIR${RESET}"
            else
                echo -e "  ${RED}Clone failed. Install manually or try again with a different path.${RESET}"
                echo -e "  ${DIM}  If the repo is private, authenticate first (gh auth login or an SSH key)${RESET}"
                echo -e "  ${DIM}  and/or set BUMBLEBEE_REPO_URL in .env to an SSH URL.${RESET}"
                echo ""
                return 1
            fi
        else
            echo -e "  ${YELLOW}Bumblebee is required to continue. Please provide a valid path or clone it.${RESET}"
            echo ""
            return 1
        fi
    fi

    echo ""
    if command -v bumblebee &>/dev/null; then
        echo -e "  ${GREEN}✔ Bumblebee CLI available: $(command -v bumblebee)${RESET}"
    else
        echo -e "  ${YELLOW}⚠  Bumblebee CLI not found in PATH.${RESET}"
        echo -e "  ${DIM}  Follow the install instructions at: $BUMBLEBEE_REPO_URL${RESET}"
    fi
    echo ""
    return 0
}

_prompt_value() {
    local label="$1" default="$2" varname="$3"
    echo -e "  ${BOLD}${label}${RESET}"
    echo -e "  ${DIM}[default: ${default}]${RESET}"
    read -re -p "  > " input_val
    printf -v "$varname" '%s' "${input_val:-$default}"
    echo ""
}

first_run_setup() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║           BSCAN — FIRST RUN SETUP WIZARD             ║"
    echo "  ╠═══════════════════════════════════════════════════════╣"
    echo "  ║  No .env found. Let's configure your environment.    ║"
    echo "  ║  Required fields are marked — others have defaults.  ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    # [1/8] Required — loop until bumblebee is confirmed present or cloned
    while true; do
        while true; do
            echo -e "  ${BOLD}[1/8] Bumblebee home directory${RESET}"
            echo -e "  ${DIM}Your local clone of the bumblebee GitHub repo ($BUMBLEBEE_REPO_URL)${RESET}"
            read -re -p "  > " BUMBLEBEE_DIR
            if [[ -n "$BUMBLEBEE_DIR" ]]; then
                BUMBLEBEE_DIR=$(_expand_path "$BUMBLEBEE_DIR")
                if [[ "$(basename "$BUMBLEBEE_DIR")" != "bumblebee" ]]; then
                    BUMBLEBEE_DIR="${BUMBLEBEE_DIR%/}/bumblebee"
                    echo -e "  ${DIM}Path adjusted to: $BUMBLEBEE_DIR${RESET}"
                fi
                break
            fi
            echo -e "  ${RED}Path is required.${RESET}\n"
        done
        echo ""
        if _ensure_bumblebee; then break; fi
    done

    # [2/8] Required — no default
    while true; do
        echo -e "  ${BOLD}[2/8] Scan root path${RESET}"
        case "$(uname -s)" in
            Linux)  _scan_eg="/home (all user directories), / (entire system)" ;;
            Darwin) _scan_eg="/Users (all user directories), / (entire system)" ;;
            *)      _scan_eg="/ (entire system), or a specific directory" ;;
        esac
        echo -e "  ${DIM}Root directory bumblebee will scan recursively (e.g. ${_scan_eg})${RESET}"
        read -re -p "  > " SCAN_ROOT
        if [[ -n "$SCAN_ROOT" ]]; then SCAN_ROOT=$(_expand_path "$SCAN_ROOT"); break; fi
        echo -e "  ${RED}Path is required.${RESET}\n"
    done
    echo ""

    # [3/8] Required — validate or create directory
    while true; do
        echo -e "  ${BOLD}[3/8] Log directory${RESET}"
        echo -e "  ${DIM}Where scan reports will be saved. Will be created if it does not exist.${RESET}"
        read -re -p "  > " LOG_DIR
        if [[ -z "$LOG_DIR" ]]; then
            echo -e "  ${RED}Path is required.${RESET}\n"; continue
        fi
        LOG_DIR=$(_expand_path "$LOG_DIR")
        if [[ -d "$LOG_DIR" ]]; then
            if [[ -w "$LOG_DIR" ]]; then
                echo -e "  ${GREEN}✔ Directory exists and is writable.${RESET}"; break
            else
                echo -e "  ${RED}Directory exists but is not writable: $LOG_DIR${RESET}\n"; continue
            fi
        else
            echo -e "  ${YELLOW}Directory not found. Creating: $LOG_DIR${RESET}"
            if mkdir -p "$LOG_DIR" 2>/dev/null && [[ -w "$LOG_DIR" ]]; then
                echo -e "  ${GREEN}✔ Directory created successfully.${RESET}"; break
            else
                echo -e "  ${RED}Could not create or write to: $LOG_DIR — check the path and permissions.${RESET}\n"; continue
            fi
        fi
    done
    echo ""

    _prompt_value "[4/8] Log retention (days)" "$DEFAULT_RETENTION_DAYS" RETENTION_DAYS

    echo -e "  ${BOLD}[5/8] Output format${RESET}  (human = dashboard, raw = NDJSON)"
    echo -e "  ${DIM}[default: human]${RESET}"
    read -re -p "  > " _fmt
    OUTPUT_FORMAT="${_fmt:-human}"
    [[ "$OUTPUT_FORMAT" != "raw" ]] && OUTPUT_FORMAT="human"
    echo ""

    echo -e "  ${BOLD}[6/8] Auto-export report after scan? [yes/no]${RESET}"
    echo -e "  ${DIM}[default: yes]${RESET}"
    read -re -p "  > " _exp
    _exp=$(echo "${_exp:-yes}" | tr '[:upper:]' '[:lower:]')
    EXPORT_REPORT=$([[ "$_exp" == "no" ]] && echo "no" || echo "yes")
    echo ""

    echo -e "  ${BOLD}[7/8] Check for bscan updates before each run? [yes/no]${RESET}"
    echo -e "  ${DIM}Offers to pull the latest bscan when your checkout is behind. [default: yes]${RESET}"
    read -re -p "  > " _sbr
    _sbr=$(echo "${_sbr:-yes}" | tr '[:upper:]' '[:lower:]')
    SYNC_BSCAN_REPO=$([[ "$_sbr" == "no" ]] && echo "no" || echo "yes")
    echo ""

    echo -e "  ${BOLD}[8/8] Sync threat catalog before each run? [yes/no]${RESET}"
    echo -e "  ${DIM}[default: yes]${RESET}"
    read -re -p "  > " _sc
    _sc=$(echo "${_sc:-yes}" | tr '[:upper:]' '[:lower:]')
    SYNC_CATALOG=$([[ "$_sc" == "no" ]] && echo "no" || echo "yes")
    echo ""

    SCAN_MODE="${SCAN_MODE:-$DEFAULT_SCAN_MODE}"
    save_config

    echo -e "${GREEN}${BOLD}  ✔ Configuration saved to: ${ENV_FILE}${RESET}"
    echo -e "${DIM}  Edit .env directly or use the config panel at any time.${RESET}"
    echo ""

    # --- Install bscan symlink ---
    _install_symlink() {
        local _target="$BSCAN_REPO_DIR/bscan.sh"
        local _bin_dir=""
        # prefer a dir already in PATH
        for _d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
            if [[ ":$PATH:" == *":$_d:"* ]]; then
                _bin_dir="$_d"; break
            fi
        done
        # fall back to ~/.local/bin even if not yet in PATH
        [[ -z "$_bin_dir" ]] && _bin_dir="$HOME/.local/bin"

        mkdir -p "$_bin_dir"
        local _link="$_bin_dir/bscan"

        if [[ -L "$_link" || -e "$_link" ]]; then
            rm -f "$_link"
        fi
        ln -s "$_target" "$_link"
        echo -e "${GREEN}  ✔ Symlink created: ${_link} → ${_target}${RESET}"

        if [[ ":$PATH:" != *":$_bin_dir:"* ]]; then
            echo -e "${YELLOW}  ⚠  ${_bin_dir} is not in your PATH.${RESET}"
            echo -e "${DIM}  Add this line to your shell rc file (~/.bashrc, ~/.zshrc, etc.):${RESET}"
            echo -e "${DIM}    export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}"
            echo -e "${DIM}  Then open a new terminal or run: source ~/.bashrc${RESET}"
        fi
    }

    echo -e "  ${BOLD}Install 'bscan' command? [yes/no]${RESET}"
    echo -e "  ${DIM}Creates a symlink so you can run 'bscan' from anywhere. [default: yes]${RESET}"
    read -re -p "  > " _inst
    _inst=$(echo "${_inst:-yes}" | tr '[:upper:]' '[:lower:]')
    if [[ "$_inst" != "no" ]]; then
        _install_symlink
    fi
    echo ""

    read -rp "  Press ENTER to continue to the scanner..."
    echo ""
}

# ---------------------------------------------------------------------------
# Boot: first-run check then load config
# ---------------------------------------------------------------------------

if [[ ! -f "$ENV_FILE" ]]; then
    first_run_setup
else
    load_config
fi

# ---------------------------------------------------------------------------
# Main Configuration Control Panel
# ---------------------------------------------------------------------------

while true; do
    clear
    echo -e "${CYAN}${BOLD}=========================================================${RESET}"
    echo -e "${CYAN}${BOLD}       BUMBLEBEE SCANNER CONFIGURATION CONTROL PANEL     ${RESET}"
    echo -e "${CYAN}${BOLD}=========================================================${RESET}"
    echo -e "  ${BOLD}[1]${RESET} Bumblebee Home Dir   : ${YELLOW}$BUMBLEBEE_DIR${RESET}"
    echo -e "  ${BOLD}[2]${RESET} System Scan Target   : ${YELLOW}$SCAN_ROOT${RESET}"
    echo -e "  ${BOLD}[3]${RESET} Target Output Format : ${YELLOW}$OUTPUT_FORMAT${RESET}"
    echo -e "  ${BOLD}[4]${RESET} Auto-Export Report   : ${YELLOW}$EXPORT_REPORT${RESET}"
    echo -e "  ${BOLD}[5]${RESET} Log Directory Path   : ${YELLOW}$LOG_DIR${RESET}"
    echo -e "  ${BOLD}[6]${RESET} Log Retention Rules  : Delete logs older than ${YELLOW}$RETENTION_DAYS${RESET} days"
    echo -e "  ${BOLD}[7]${RESET} Check bscan Updates  : ${YELLOW}$SYNC_BSCAN_REPO${RESET}"
    echo -e "  ${BOLD}[8]${RESET} Sync Threat Catalog  : ${YELLOW}$SYNC_CATALOG${RESET}"
    echo -e "  ${BOLD}[9]${RESET} Scan Output Mode     : ${YELLOW}$SCAN_MODE${RESET}"
    echo -e "  ${BOLD}[0]${RESET} Reset to Defaults"
    echo -e "${CYAN}---------------------------------------------------------${RESET}"
    echo -e "  ${GREEN}${BOLD}[P] PROCEED TO RUN SCAN${RESET}  |  ${RED}[Q] QUIT PROGRAM${RESET}"
    echo -e "${CYAN}=========================================================${RESET}"
    echo ""
    read -rp "Select an option to change, [P] to run, or [Q] to quit: " main_choice
    main_choice=$(echo "$main_choice" | tr '[:upper:]' '[:lower:]')

    case "$main_choice" in
        1)
            read -rp "Enter new Bumblebee Directory Path: " input_val
            if [[ -n "$input_val" ]]; then
                input_val=$(_expand_path "$input_val")
                [[ ! -d "$input_val" ]] && echo -e "${YELLOW}Warning: Directory does not exist yet. Saving anyway.${RESET}"
                BUMBLEBEE_DIR="$input_val"; save_config
            fi
            ;;
        2)
            read -rp "Enter new System Scan Target Path: " input_val
            if [[ -n "$input_val" ]]; then
                input_val=$(_expand_path "$input_val")
                if [[ ! -d "$input_val" ]]; then
                    echo -e "${RED}Error: Target path does not exist: $input_val${RESET}"; sleep 1; continue
                fi
                SCAN_ROOT="$input_val"; save_config
            fi
            ;;
        3)
            echo "  Select Output Format:"
            echo "    1) human (Clean Visual Dashboard)"
            echo "    2) raw   (Original NDJSON Objects)"
            read -rp "Choose format [1-2]: " fmt_val
            if [[ "$fmt_val" == "2" ]]; then OUTPUT_FORMAT="raw"; else OUTPUT_FORMAT="human"; fi
            save_config
            ;;
        4)
            read -rp "Enable automatic log exports? [yes/no]: " input_val
            input_val=$(echo "$input_val" | tr '[:upper:]' '[:lower:]')
            if [[ "$input_val" == "yes" || "$input_val" == "no" ]]; then EXPORT_REPORT="$input_val"; save_config; fi
            ;;
        5)
            read -rp "Enter new Log Directory Path: " input_val
            if [[ -n "$input_val" ]]; then LOG_DIR=$(_expand_path "$input_val"); save_config; fi
            ;;
        6)
            read -rp "Enter number of days to retain logs (e.g., 180): " input_val
            if [[ "$input_val" =~ ^[0-9]+$ ]]; then RETENTION_DAYS="$input_val"; save_config; fi
            ;;
        7)
            read -rp "Sync bscan repo before each run? [yes/no]: " input_val
            input_val=$(echo "$input_val" | tr '[:upper:]' '[:lower:]')
            if [[ "$input_val" == "yes" || "$input_val" == "no" ]]; then SYNC_BSCAN_REPO="$input_val"; save_config; fi
            ;;
        8)
            read -rp "Sync threat catalog before each run? [yes/no]: " input_val
            input_val=$(echo "$input_val" | tr '[:upper:]' '[:lower:]')
            if [[ "$input_val" == "yes" || "$input_val" == "no" ]]; then SYNC_CATALOG="$input_val"; save_config; fi
            ;;
        9)
            echo "  Select Scan Output Mode:"
            echo "    1) spinner  (Rotating indicator + elapsed time)"
            echo "    2) verbose  (Live raw output from bumblebee)"
            read -rp "Choose mode [1-2]: " mode_val
            if [[ "$mode_val" == "2" ]]; then SCAN_MODE="verbose"; else SCAN_MODE="spinner"; fi
            save_config
            ;;
        0)
            read -rp "Reset all settings to defaults? [y/N]: " confirm_reset
            confirm_reset=$(echo "$confirm_reset" | tr '[:upper:]' '[:lower:]')
            if [[ "$confirm_reset" == "y" || "$confirm_reset" == "yes" ]]; then reset_config; fi
            ;;
        p|"")
            break
            ;;
        q)
            echo "Exiting program safely."
            exit 0
            ;;
        *)
            echo "Invalid selection. Press enter to refresh." && read -r
            ;;
    esac
done

CATALOG_PATH="${BUMBLEBEE_DIR}/threat_intel/"
SCAN_START=$(date +%s)

# ---------------------------------------------------------------------------
# Profile Selection
# ---------------------------------------------------------------------------

echo ""
echo -e "${CYAN}${BOLD}Select Bumblebee Scan Profile:${RESET}"
echo "  1) Baseline          (Quick global packages/extensions checklist)"
echo "  2) Project           (Targeted workspace/lockfile inspection)"
echo -e "  3) Deep ${BOLD}[DEFAULT]${RESET}    (Aggressive cross-user ecosystem sweep)"
echo "  4) Incident Response (Targeted emergency vulnerability triage)"
echo ""
read -rp "Choose a profile [1-4, Default: 3]: " profile_choice

case "$profile_choice" in
    1) SCAN_PROFILE="baseline" ;;
    2) SCAN_PROFILE="project" ;;
    4) SCAN_PROFILE="incident-response" ;;
    *) SCAN_PROFILE="deep" ;;
esac

echo ""
echo -e "Selected Profile: ${YELLOW}${BOLD}$SCAN_PROFILE${RESET}"

if [[ "$SCAN_ROOT" == "/" ]]; then
    echo -e "${YELLOW}${BOLD}⚠  Warning:${RESET}${YELLOW} Scan root is / (filesystem root). This will scan every file on the system and may take a very long time.${RESET}"
    echo ""
fi

read -rp "Confirm launching '$SCAN_PROFILE' scan on '$SCAN_ROOT'? [Y/n]: " final_confirm
final_confirm=$(echo "$final_confirm" | tr '[:upper:]' '[:lower:]')

if [[ -n "$final_confirm" && "$final_confirm" != "y" && "$final_confirm" != "yes" ]]; then
    echo "Scan canceled."
    exit 0
fi

# ---------------------------------------------------------------------------
# Repository Sync
# ---------------------------------------------------------------------------

echo ""
if [[ "$SYNC_BSCAN_REPO" == "yes" ]]; then
    echo -e "${CYAN}==> Checking for bscan updates...${RESET}"
    if ! git -C "$BSCAN_REPO_DIR" rev-parse --git-dir &>/dev/null; then
        echo -e "${YELLOW}-- Not a git checkout; skipping update check.${RESET}"
    elif ! git -C "$BSCAN_REPO_DIR" fetch --quiet 2>/dev/null; then
        echo -e "${YELLOW}-- Could not reach remote; skipping update check.${RESET}"
    else
        _branch=$(git -C "$BSCAN_REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
        _upstream=$(git -C "$BSCAN_REPO_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
        if [[ -z "$_upstream" ]]; then
            echo -e "${YELLOW}-- No upstream tracking branch for '$_branch'; skipping.${RESET}"
        else
            _behind=$(git -C "$BSCAN_REPO_DIR" rev-list --count "HEAD..$_upstream" 2>/dev/null || echo 0)
            if [[ "$_behind" -gt 0 ]]; then
                echo -e "${YELLOW}  bscan is $_behind commit(s) behind $_upstream.${RESET}"
                read -rp "  Update now? [Y/n]: " _upd_yn
                _upd_yn=$(echo "${_upd_yn:-y}" | tr '[:upper:]' '[:lower:]')
                if [[ "$_upd_yn" == "y" || "$_upd_yn" == "yes" ]]; then
                    if git -C "$BSCAN_REPO_DIR" pull --ff-only; then
                        echo -e "${GREEN}  ✔ bscan updated. Re-run to use the latest version.${RESET}"
                        exit 0
                    else
                        echo -e "${RED}  Update failed (local changes?). Resolve manually with: git -C \"$BSCAN_REPO_DIR\" pull${RESET}"
                    fi
                else
                    echo -e "${DIM}  Skipped update.${RESET}"
                fi
            else
                echo -e "${GREEN}  ✔ bscan is up to date.${RESET}"
            fi
        fi
    fi
else
    echo -e "${YELLOW}-- bscan update check skipped (disabled in config)${RESET}"
fi

if [[ "$SYNC_CATALOG" == "yes" ]]; then
    echo -e "${CYAN}==> Syncing threat catalog...${RESET}"
    if [[ -d "$BUMBLEBEE_DIR" ]] && git -C "$BUMBLEBEE_DIR" rev-parse --git-dir &>/dev/null; then
        git -C "$BUMBLEBEE_DIR" pull
    else
        echo -e "${YELLOW}Bumblebee repo not found at: $BUMBLEBEE_DIR${RESET}"
        read -rp "  Clone it now? [Y/n]: " _reclone_yn
        _reclone_yn=$(echo "${_reclone_yn:-y}" | tr '[:upper:]' '[:lower:]')
        if [[ "$_reclone_yn" == "y" || "$_reclone_yn" == "yes" ]]; then
            echo -e "${CYAN}  Cloning $BUMBLEBEE_REPO_URL into $BUMBLEBEE_DIR ...${RESET}"
            if git clone "$BUMBLEBEE_REPO_URL" "$BUMBLEBEE_DIR"; then
                echo -e "${GREEN}  ✔ Cloned successfully.${RESET}"
            else
                echo -e "${RED}  Clone failed. Fix BUMBLEBEE_DIR/BUMBLEBEE_REPO_URL in .env and re-run.${RESET}"; exit 1
            fi
        else
            echo -e "${RED}ERROR: Bumblebee repo required. Fix BUMBLEBEE_DIR in .env and re-run.${RESET}"; exit 1
        fi
    fi
else
    echo -e "${YELLOW}-- Threat catalog sync skipped (disabled in config)${RESET}"
fi

if [[ ! -d "$CATALOG_PATH" ]]; then
    echo -e "${RED}ERROR: Threat catalog missing at $CATALOG_PATH${RESET}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Log Housekeeping
# ---------------------------------------------------------------------------

if [[ -d "$LOG_DIR" ]]; then
    echo -e "${CYAN}==> Performing Log Purge (entries older than $RETENTION_DAYS days)...${RESET}"
    find "$LOG_DIR" -type f -name "*.txt"    -mtime +"$RETENTION_DAYS" -exec rm -f {} \;
    find "$LOG_DIR" -type f -name "*.ndjson" -mtime +"$RETENTION_DAYS" -exec rm -f {} \;
fi

# ---------------------------------------------------------------------------
# Scan Execution
# ---------------------------------------------------------------------------

_spinner() {
    local pid=$1 frames='-\|/' i=0 secs=0
    while kill -0 "$pid" 2>/dev/null; do
        secs=$(( $(date +%s) - SCAN_START ))
        printf "\r  ${CYAN}[${frames:$i:1}]${RESET} Scanning... %ds elapsed" "$secs"
        i=$(( (i + 1) % 4 ))
        sleep 0.15
    done
    printf "\r%-60s\r" ""
}

echo ""
echo -e "${CYAN}==> Launching ${BOLD}$SCAN_PROFILE${RESET}${CYAN} sweep on ${BOLD}$SCAN_ROOT${RESET}${CYAN}...${RESET}"
echo ""

SCAN_TMPFILE=$(mktemp)

if [[ "$SCAN_MODE" == "verbose" ]]; then
    set +e
    sudo bumblebee scan \
      --profile "$SCAN_PROFILE" \
      --root "$SCAN_ROOT" \
      --exposure-catalog "$CATALOG_PATH" 2>&1 | tee "$SCAN_TMPFILE"
    SCAN_EXIT="${PIPESTATUS[0]}"
    set -e
else
    sudo bumblebee scan \
      --profile "$SCAN_PROFILE" \
      --root "$SCAN_ROOT" \
      --exposure-catalog "$CATALOG_PATH" > "$SCAN_TMPFILE" 2>&1 &
    SCAN_PID=$!
    _spinner "$SCAN_PID"
    wait "$SCAN_PID" && SCAN_EXIT=0 || SCAN_EXIT=$?
fi

RAW_OUTPUT=$(cat "$SCAN_TMPFILE")

if [[ "$SCAN_EXIT" -ne 0 ]]; then
    echo -e "${RED}ERROR: Scan exited with code $SCAN_EXIT${RESET}"
    [[ "$SCAN_MODE" != "verbose" ]] && echo "$RAW_OUTPUT" >&2
    exit "$SCAN_EXIT"
fi

SCAN_END=$(date +%s)
ELAPSED=$(( SCAN_END - SCAN_START ))

# ---------------------------------------------------------------------------
# Output Formatters
# ---------------------------------------------------------------------------

_parse_findings() {
    if command -v jq &>/dev/null; then
        echo "$RAW_OUTPUT" | jq -r '
            select(.record_type == "finding") |
            "  • [\(.ecosystem | ascii_upcase)] \(.name) (v\(.version)) found at: \(.path)"
        ' 2>/dev/null
    else
        echo "$RAW_OUTPUT" | awk -F'"' '/"record_type":"finding"/{
            name=""; version=""; ecosystem=""; path="";
            for(i=1;i<=NF;i++){
                if($i=="name")      name=$(i+2);
                if($i=="version")   version=$(i+2);
                if($i=="ecosystem") ecosystem=$(i+2);
                if($i=="path")      path=$(i+2);
            }
            printf "  • [%s] %s (v%s) found at: %s\n", toupper(ecosystem), name, version, path
        }' | sed 's/\\//g'
    fi
}

_parse_summary() {
    if command -v jq &>/dev/null; then
        echo "$RAW_OUTPUT" | jq -r '
            select(.record_type == "scan_summary") |
            "  Files Audited      : \(.files_considered // "N/A")\n  Packages Checked   : \(.package_records_suppressed // "N/A")\n  Engine Status      : \(.status // "N/A")"
        ' 2>/dev/null
    else
        echo "$RAW_OUTPUT" | awk -F',' '/"record_type":"scan_summary"/{
            for(i=1;i<=NF;i++){
                if($i~/"files_considered"/)           print "  Files Audited      : " $i;
                if($i~/"package_records_suppressed"/) print "  Packages Checked   : " $i;
                if($i~/"status"/)                     print "  Engine Status      : " $i;
            }
        }' | sed -E 's/"//g; s/[{}]//g; s/^[[:space:]]*//'
    fi
}

FINDINGS=$(_parse_findings)
FINDING_COUNT=$(echo "$FINDINGS" | grep -c '•' || true)

HUMAN_DASHBOARD=$(cat << DASHBOARD
========================================================
               BUMBLEBEE SCAN REPORT
========================================================
Generated : $(date '+%Y-%m-%d %H:%M:%S')
Target    : $SCAN_ROOT
Profile   : $SCAN_PROFILE
Elapsed   : ${ELAPSED}s
--------------------------------------------------------
⚠️  MALICIOUS COMPROMISES / FINDINGS DETECTED: ($FINDING_COUNT found)
--------------------------------------------------------
${FINDINGS:-  🟢 Clear! No known threat catalog compromises detected.}

📊 SCAN PERFORMANCE METRICS:
--------------------------------------------------------
$(_parse_summary)
========================================================
DASHBOARD
)

if [[ "$OUTPUT_FORMAT" == "raw" ]]; then
    echo "$RAW_OUTPUT"
else
    echo "$HUMAN_DASHBOARD"
fi

if [[ "$FINDING_COUNT" -gt 0 ]]; then
    echo -e "\n${RED}${BOLD}[!] ALERT: $FINDING_COUNT finding(s) detected. Review the report above.${RESET}"
fi

# ---------------------------------------------------------------------------
# Automated Export
# ---------------------------------------------------------------------------

if [[ "$EXPORT_REPORT" == "yes" ]]; then
    mkdir -p "$LOG_DIR"
    TIMESTAMP=$(date '+%Y_%m_%d_%H%M%S')

    if [[ "$OUTPUT_FORMAT" == "raw" ]]; then
        FILE_EXTENSION="ndjson"
        OUTPUT_CONTENT="$RAW_OUTPUT"
    else
        FILE_EXTENSION="txt"
        OUTPUT_CONTENT="$HUMAN_DASHBOARD"
    fi

    EXPORT_TARGET="${LOG_DIR}/${TIMESTAMP}_bumblebee_report.${FILE_EXTENSION}"
    echo "$OUTPUT_CONTENT" > "$EXPORT_TARGET"
    echo ""
    echo -e "${GREEN}💾 Report archived to: $EXPORT_TARGET${RESET}"
fi

echo ""
echo -e "${GREEN}==> Execution complete. Total elapsed: ${ELAPSED}s${RESET}"
