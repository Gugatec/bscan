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

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

# Remove every line in any known rc file that contains a fixed string.
_remove_from_rc() {
    local _pattern="$1"
    local _rc _tmp
    for _rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        if [[ -f "$_rc" ]] && grep -qF "$_pattern" "$_rc" 2>/dev/null; then
            _tmp=$(mktemp)
            grep -vF "$_pattern" "$_rc" > "$_tmp" && mv "$_tmp" "$_rc"
            echo -e "  ${GREEN}  ✔ Removed from $_rc${RESET}"
        fi
    done
}

_uninstall_step() {
    local _label="$1"
    echo ""
    echo -e "  ${BOLD}$_label${RESET}"
    read -rp "  Remove? [y/N]: " _yn
    echo "${_yn:-n}" | tr '[:upper:]' '[:lower:]'
}

_run_uninstall() {
    clear
    echo -e "${RED}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║               BSCAN — UNINSTALL WIZARD               ║"
    echo "  ╠═══════════════════════════════════════════════════════╣"
    echo "  ║  Choose how to proceed:                               ║"
    echo "  ║    [1] Step-by-step  — confirm each component        ║"
    echo "  ║    [2] Full removal  — remove everything at once     ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    read -rp "  Select mode [1/2] or ENTER to cancel: " _mode
    case "${_mode:-}" in
        1) _mode="step" ;;
        2)
            echo ""
            echo -e "  ${RED}${BOLD}⚠  Full removal will uninstall ALL components listed below.${RESET}"
            echo -e "  ${DIM}  symlink · log folder · bumblebee repo · Go · Homebrew · bscan itself${RESET}"
            echo ""
            read -rp "  Are you sure? [y/N]: " _fc1
            if [[ ! "${_fc1:-n}" =~ ^[Yy] ]]; then echo -e "  ${DIM}Cancelled.${RESET}"; sleep 1; return; fi
            read -rp "  Confirm full removal — this cannot be undone. [y/N]: " _fc2
            if [[ ! "${_fc2:-n}" =~ ^[Yy] ]]; then echo -e "  ${DIM}Cancelled.${RESET}"; sleep 1; return; fi
            _mode="full"
            ;;
        *) echo -e "  ${DIM}Cancelled.${RESET}"; sleep 1; return ;;
    esac

    # In full mode every step runs automatically; in step mode each is confirmed.
    _should_run() {
        local _label="$1"
        if [[ "$_mode" == "full" ]]; then
            echo -e "  ${CYAN}  → $_label${RESET}"
            return 0
        fi
        [[ "$(_uninstall_step "$_label")" =~ ^y ]]
    }

    echo ""
    local _remove_bscan=n

    # 1. bscan symlink
    if _should_run "1. Remove bscan command symlink"; then
        local _removed=0
        for _d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
            if [[ -L "$_d/bscan" ]]; then
                rm -f "$_d/bscan"
                echo -e "  ${GREEN}  ✔ Removed: $_d/bscan${RESET}"
                _removed=1
            fi
        done
        [[ "$_removed" -eq 0 ]] && echo -e "  ${DIM}  No symlink found.${RESET}"
    fi

    # 2. bscan log folder
    if _should_run "2. Remove bscan log folder ($LOG_DIR)"; then
        if [[ -d "$LOG_DIR" ]]; then
            rm -rf "$LOG_DIR"
            echo -e "  ${GREEN}  ✔ Removed: $LOG_DIR${RESET}"
        else
            echo -e "  ${DIM}  Log folder not found: $LOG_DIR${RESET}"
        fi
    fi

    # 3. Bumblebee repo
    if _should_run "3. Remove bumblebee repo ($BUMBLEBEE_DIR)"; then
        if [[ -d "$BUMBLEBEE_DIR" ]]; then
            rm -rf "$BUMBLEBEE_DIR"
            echo -e "  ${GREEN}  ✔ Removed: $BUMBLEBEE_DIR${RESET}"
        else
            echo -e "  ${DIM}  Bumblebee repo not found: $BUMBLEBEE_DIR${RESET}"
        fi
    fi

    # 4. Uninstall Go
    if _should_run "4. Uninstall Go (via Homebrew) and remove PATH entries from rc files"; then
        if command -v brew &>/dev/null && brew list go &>/dev/null 2>&1; then
            echo -e "  ${CYAN}  Uninstalling Go via Homebrew...${RESET}"
            brew uninstall go && echo -e "  ${GREEN}  ✔ Go uninstalled.${RESET}" \
                              || echo -e "  ${RED}  brew uninstall go failed.${RESET}"
        else
            echo -e "  ${DIM}  Go does not appear to be managed by Homebrew — skipping brew uninstall.${RESET}"
        fi
        # Remove GOPATH/bin PATH entries regardless of how Go was installed
        local _gopath_bin
        _gopath_bin="${GOPATH:-$HOME/go}/bin"
        _remove_from_rc "$_gopath_bin"
        _remove_from_rc 'GOPATH'
        echo -e "  ${GREEN}  ✔ Go PATH entries removed from rc files.${RESET}"
    fi

    # 5. Uninstall Homebrew
    if _should_run "5. Uninstall Homebrew and remove shell env entries from rc files"; then
        if command -v brew &>/dev/null; then
            echo -e "  ${CYAN}  Running Homebrew uninstall script...${RESET}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" \
                && echo -e "  ${GREEN}  ✔ Homebrew uninstalled.${RESET}" \
                || echo -e "  ${RED}  Homebrew uninstall script failed — check output above.${RESET}"
        else
            echo -e "  ${DIM}  Homebrew not found — skipping.${RESET}"
        fi
        _remove_from_rc 'brew shellenv'
        echo -e "  ${GREEN}  ✔ Homebrew shell env entries removed from rc files.${RESET}"
    fi

    # 6. Remove bscan itself
    echo ""
    echo -e "  ${BOLD}6. Remove bscan itself ($BSCAN_REPO_DIR)${RESET}"
    echo -e "  ${DIM}  This directory contains the script currently running.${RESET}"
    echo -e "  ${DIM}  Removal is scheduled for after bscan exits.${RESET}"
    local _do_remove_bscan=n
    if [[ "$_mode" == "full" ]]; then
        echo -e "  ${CYAN}  → Scheduled for removal after exit.${RESET}"
        _do_remove_bscan=y
    else
        read -rp "  Remove? [y/N]: " _yn6
        [[ "${_yn6:-n}" =~ ^[Yy] ]] && _do_remove_bscan=y
    fi
    if [[ "$_do_remove_bscan" == "y" ]]; then
        _remove_bscan=y
        echo -e "  ${GREEN}  ✔ Removal scheduled.${RESET}"
        # Write a self-contained cleanup script to /tmp
        local _cleanup_script="/tmp/bscan_cleanup_$$.sh"
        cat > "$_cleanup_script" << CLEANUP
#!/usr/bin/env bash
sleep 1
rm -rf "$BSCAN_REPO_DIR"
rm -f "$_cleanup_script"
echo "bscan removed."
CLEANUP
        chmod +x "$_cleanup_script"
        echo -e "  ${DIM}  Will run automatically after bscan exits:${RESET}"
        echo -e "  ${DIM}    $_cleanup_script${RESET}"
    fi

    echo ""
    echo -e "${CYAN}  Uninstall complete. Summary above shows what was removed.${RESET}"
    echo ""
    read -rp "  Press ENTER to continue..."

    if [[ "$_remove_bscan" == "y" ]]; then
        echo -e "${DIM}Removing bscan...${RESET}"
        # Launch cleanup in background then exit
        bash "/tmp/bscan_cleanup_$$.sh" &
        exit 0
    fi
}

reconfigure() {
    echo ""
    echo -e "  ${RED}${BOLD}⚠  RECONFIGURE TO DEFAULTS${RESET}"
    echo -e "  ${DIM}This will DELETE your current .env and re-run the setup wizard.${RESET}"
    echo -e "  ${DIM}All saved settings will be permanently lost.${RESET}"
    echo ""
    read -rp "  Are you sure? This cannot be undone. [y/N]: " _c1
    _c1=$(echo "$_c1" | tr '[:upper:]' '[:lower:]')
    if [[ "$_c1" != "y" && "$_c1" != "yes" ]]; then
        echo -e "  ${DIM}Cancelled.${RESET}"; sleep 1; return
    fi
    echo ""
    read -rp "  Confirm again — delete .env and start over? [y/N]: " _c2
    _c2=$(echo "$_c2" | tr '[:upper:]' '[:lower:]')
    if [[ "$_c2" != "y" && "$_c2" != "yes" ]]; then
        echo -e "  ${DIM}Cancelled.${RESET}"; sleep 1; return
    fi
    rm -f "$ENV_FILE"
    echo -e "${GREEN}  ✔ .env removed. Launching setup wizard...${RESET}"
    sleep 1
    first_run_setup
    load_config
}

# ---------------------------------------------------------------------------
# Symlink management
# ---------------------------------------------------------------------------

_install_symlink() {
    local _target="$BSCAN_REPO_DIR/bscan.sh"
    local _bin_dir=""
    for _d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
        if [[ ":$PATH:" == *":$_d:"* ]]; then
            _bin_dir="$_d"; break
        fi
    done
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

_symlink_status() {
    local _link
    for _d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
        _link="$_d/bscan"
        if [[ -L "$_link" ]]; then
            echo "$_link → $(readlink "$_link")"
            return
        fi
    done
    echo "not installed"
}

_manage_symlink() {
    local _status
    _status=$(_symlink_status)
    echo ""
    echo -e "  ${BOLD}bscan symlink:${RESET} ${YELLOW}${_status}${RESET}"
    echo ""
    echo "    1) Install / recreate symlink"
    echo "    2) Remove symlink"
    read -rp "  Choose [1-2] or ENTER to cancel: " _lc
    case "$_lc" in
        1) _install_symlink ;;
        2)
            local _removed=0
            for _d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
                if [[ -L "$_d/bscan" ]]; then
                    rm -f "$_d/bscan"
                    echo -e "${GREEN}  ✔ Removed: ${_d}/bscan${RESET}"
                    _removed=1
                fi
            done
            [[ "$_removed" -eq 0 ]] && echo -e "${DIM}  No symlink found to remove.${RESET}"
            ;;
        *) echo -e "${DIM}  Cancelled.${RESET}" ;;
    esac
    sleep 1
}

# ---------------------------------------------------------------------------
# First-run setup wizard
# ---------------------------------------------------------------------------

_find_bumblebee_bin() {
    if command -v bumblebee &>/dev/null; then
        command -v bumblebee; return 0
    fi
    if [[ -n "${GOBIN:-}" && -x "$GOBIN/bumblebee" ]]; then
        echo "$GOBIN/bumblebee"; return 0
    fi
    if [[ -n "${GOPATH:-}" && -x "$GOPATH/bin/bumblebee" ]]; then
        echo "$GOPATH/bin/bumblebee"; return 0
    fi
    if [[ -x "$HOME/go/bin/bumblebee" ]]; then
        echo "$HOME/go/bin/bumblebee"; return 0
    fi
    if [[ -n "${BUMBLEBEE_DIR:-}" && -x "$BUMBLEBEE_DIR/bumblebee" ]]; then
        echo "$BUMBLEBEE_DIR/bumblebee"; return 0
    fi
    return 1
}

# Detect the user's shell rc file (zshrc preferred, bashrc fallback)
_shell_rc() {
    case "${SHELL:-}" in
        */zsh)  echo "$HOME/.zshrc" ;;
        */bash) echo "$HOME/.bashrc" ;;
        *)
            # fall back: prefer whichever exists, else .bashrc
            if [[ -f "$HOME/.zshrc" ]]; then echo "$HOME/.zshrc"
            else echo "$HOME/.bashrc"; fi
            ;;
    esac
}

# Append a line to a file only if it is not already present
_append_if_missing() {
    local file="$1" line="$2"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
        echo -e "  ${DIM}  Added to $file: $line${RESET}"
    else
        echo -e "  ${DIM}  Already present in $file — skipped.${RESET}"
    fi
}

# Install Linux Homebrew dependencies via the available package manager.
# Returns 1 and prints instructions if no supported package manager is found.
_install_brew_linux_deps() {
    local _pkgs="build-essential procps curl file git"
    echo -e "  ${CYAN}Installing Homebrew dependencies...${RESET}"

    if command -v apt-get &>/dev/null; then
        echo -e "  ${DIM}  Detected: apt (Debian / Ubuntu)${RESET}"
        sudo apt-get update -qq && sudo apt-get install -y build-essential procps curl file git
    elif command -v dnf &>/dev/null; then
        echo -e "  ${DIM}  Detected: dnf (Fedora / RHEL 8+)${RESET}"
        sudo dnf groupinstall -y "Development Tools" && \
        sudo dnf install -y procps-ng curl file git
    elif command -v yum &>/dev/null; then
        echo -e "  ${DIM}  Detected: yum (CentOS / RHEL 7)${RESET}"
        sudo yum groupinstall -y "Development Tools" && \
        sudo yum install -y procps-ng curl file git
    elif command -v zypper &>/dev/null; then
        echo -e "  ${DIM}  Detected: zypper (openSUSE)${RESET}"
        sudo zypper install -y gcc make curl file git procps
    elif command -v pacman &>/dev/null; then
        echo -e "  ${DIM}  Detected: pacman (Arch)${RESET}"
        sudo pacman -Sy --noconfirm base-devel curl file git procps-ng
    else
        echo -e "  ${RED}Could not detect a supported package manager.${RESET}"
        echo -e "  ${YELLOW}Install the following packages manually, then re-run bscan:${RESET}"
        echo -e "  ${DIM}  $_pkgs${RESET}"
        echo -e "  ${DIM}  (package names may vary — consult your distro docs)${RESET}"
        return 1
    fi
}

# Install Homebrew and wire it into the shell rc
_install_homebrew() {
    local _rc
    _rc=$(_shell_rc)

    # On Linux, install system dependencies first
    if [[ "$(uname -s)" == "Linux" ]]; then
        echo -e "  ${YELLOW}Linux detected — Homebrew requires system packages before it can install.${RESET}"
        echo ""
        echo -e "  ${BOLD}  Install Homebrew dependencies via your package manager now? [Y/n]${RESET}"
        echo -e "  ${DIM}  Required: build-essential procps curl file git (names vary by distro)${RESET}"
        read -rp "  > " _dep_yn
        _dep_yn=$(echo "${_dep_yn:-y}" | tr '[:upper:]' '[:lower:]')
        if [[ "$_dep_yn" == "y" || "$_dep_yn" == "yes" ]]; then
            echo ""
            if ! _install_brew_linux_deps; then
                echo -e "  ${RED}Dependency install failed or skipped. Install them manually, then re-run bscan.${RESET}"
                return 1
            fi
            echo -e "  ${GREEN}✔ Dependencies installed.${RESET}"
        else
            echo -e "  ${YELLOW}Skipped. Install these packages first, then re-run bscan:${RESET}"
            echo -e "  ${DIM}  build-essential procps curl file git${RESET}"
            return 1
        fi
        echo ""
    fi

    echo -e "  ${CYAN}Installing Homebrew...${RESET}"
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        echo -e "  ${RED}Homebrew installation failed.${RESET}"
        return 1
    fi

    # Determine brew prefix
    local _brew_prefix
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        _brew_prefix="/opt/homebrew"                        # macOS Apple Silicon
    elif [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
        _brew_prefix="/home/linuxbrew/.linuxbrew"           # Linux
    elif [[ -x "/usr/local/bin/brew" ]]; then
        _brew_prefix="/usr/local"                           # macOS Intel
    else
        echo -e "  ${RED}Could not locate brew binary after install.${RESET}"
        return 1
    fi

    local _shellenv_line="eval \"\$(${_brew_prefix}/bin/brew shellenv)\""
    touch "$_rc"
    _append_if_missing "$_rc" "$_shellenv_line"

    # Activate for the current session
    eval "$("${_brew_prefix}/bin/brew" shellenv)"
    echo -e "  ${GREEN}✔ Homebrew installed: $_brew_prefix${RESET}"
    echo -e "  ${GREEN}✔ Shell env written to $_rc${RESET}"
}

# Install Go via Homebrew and wire GOPATH/bin into the shell rc
_install_go() {
    if ! command -v brew &>/dev/null; then
        echo -e "  ${RED}Homebrew not found — cannot install Go automatically.${RESET}"
        return 1
    fi
    echo -e "  ${CYAN}Installing Go via Homebrew...${RESET}"
    if ! brew install go; then
        echo -e "  ${RED}Go installation failed.${RESET}"
        return 1
    fi

    # Reload brew-managed shell env so 'go' is visible now
    eval "$(brew shellenv)"

    local _gopath_bin _rc
    _gopath_bin="$(go env GOPATH)/bin"
    _rc=$(_shell_rc)
    touch "$_rc"
    _append_if_missing "$_rc" "export PATH=\"${_gopath_bin}:\$PATH\""

    export PATH="${_gopath_bin}:$PATH"
    echo -e "  ${GREEN}✔ Go installed: $(go version)${RESET}"
    echo -e "  ${GREEN}✔ GOPATH/bin added to PATH and written to $_rc${RESET}"
}

# Expand shell variables and ~, then anchor relative paths to $HOME.
_normalize_path() {
    local _p
    _p=$(eval echo "$1")
    [[ "$_p" != /* ]] && _p="$HOME/$_p"
    echo "$_p"
}

# Validate a directory: create it if missing, confirm it is writable.
# Prints status lines. Returns 0 on success, 1 on failure.
_validate_writable_dir() {
    local _dir="$1"
    if [[ -d "$_dir" ]]; then
        if [[ -w "$_dir" ]]; then
            echo -e "  ${GREEN}✔ Directory exists and is writable.${RESET}"
            return 0
        else
            echo -e "  ${RED}Directory exists but is not writable: $_dir${RESET}"
            return 1
        fi
    else
        echo -e "  ${YELLOW}Directory not found. Creating: $_dir${RESET}"
        if mkdir -p "$_dir" 2>/dev/null && [[ -w "$_dir" ]]; then
            echo -e "  ${GREEN}✔ Directory created successfully.${RESET}"
            return 0
        else
            echo -e "  ${RED}Could not create or write to: $_dir — check permissions.${RESET}"
            return 1
        fi
    fi
}

# Interactive log-directory prompt: normalize, offer /bscan append,
# validate/create, check writable. Writes result into LOG_DIR.
# Used by both the setup wizard and the menu.
_set_log_dir() {
    while true; do
        read -re -p "  > " _raw_log
        if [[ -z "$_raw_log" ]]; then
            echo -e "  ${RED}Path is required.${RESET}\n"; continue
        fi
        LOG_DIR=$(_normalize_path "$_raw_log")
        if [[ "$(basename "$LOG_DIR")" != "bscan" ]]; then
            read -rp "  Append '/bscan' to path? [Y/n]: " _app
            _app=$(echo "${_app:-y}" | tr '[:upper:]' '[:lower:]')
            if [[ "$_app" != "n" && "$_app" != "no" ]]; then
                LOG_DIR="${LOG_DIR%/}/bscan"
                echo -e "  ${DIM}Path adjusted to: $LOG_DIR${RESET}"
            fi
        fi
        _validate_writable_dir "$LOG_DIR" && break
        echo ""
    done
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
                BUMBLEBEE_DIR=$(_normalize_path "$_clone_dest")
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

    # --- Ensure Go is available, installing Homebrew + Go if needed ---
    echo ""
    if ! command -v go &>/dev/null; then
        echo -e "  ${YELLOW}⚠  Go is not installed — required to install the bumblebee CLI.${RESET}"
        echo ""
        echo -e "  ${BOLD}  Install Go automatically? (Homebrew will be installed first if needed) [Y/n]${RESET}"
        read -rp "  > " _inst_go
        _inst_go=$(echo "${_inst_go:-y}" | tr '[:upper:]' '[:lower:]')
        if [[ "$_inst_go" == "y" || "$_inst_go" == "yes" ]]; then
            echo ""
            if ! command -v brew &>/dev/null; then
                echo -e "  ${YELLOW}Homebrew not found — installing it first.${RESET}"
                echo ""
                _install_homebrew || return 1
                echo ""
            fi
            _install_go || return 1
        else
            echo -e "  ${DIM}  Skipped. Install Go manually: https://go.dev/dl/${RESET}"
            echo -e "  ${DIM}  Then run: go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest${RESET}"
            echo ""
            return 0
        fi
    fi

    # --- Install bumblebee CLI via go install if not already present ---
    local _bb_bin
    if _bb_bin=$(_find_bumblebee_bin); then
        echo -e "  ${GREEN}✔ Bumblebee CLI available: $_bb_bin${RESET}"
    else
        echo -e "  ${YELLOW}⚠  Bumblebee CLI not found.${RESET}"
        echo ""
        echo -e "  ${BOLD}  Install bumblebee CLI via 'go install'? [Y/n]${RESET}"
        echo -e "  ${DIM}  go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest${RESET}"
        read -rp "  > " _go_inst
        _go_inst=$(echo "${_go_inst:-y}" | tr '[:upper:]' '[:lower:]')
        if [[ "$_go_inst" == "y" || "$_go_inst" == "yes" ]]; then
            echo ""
            echo -e "  ${CYAN}Installing bumblebee...${RESET}"
            local _gopath_bin _rc
            _gopath_bin="$(go env GOPATH)/bin"
            _rc=$(_shell_rc)
            if go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest; then
                export PATH="${_gopath_bin}:$PATH"
                touch "$_rc"
                _append_if_missing "$_rc" "export PATH=\"${_gopath_bin}:\$PATH\""
                if _bb_bin=$(_find_bumblebee_bin); then
                    echo -e "  ${GREEN}✔ Bumblebee CLI installed: $_bb_bin${RESET}"
                else
                    echo -e "  ${YELLOW}⚠  Installed but binary not found yet — open a new terminal and re-run.${RESET}"
                fi
            else
                echo -e "  ${RED}Installation failed. Try manually:${RESET}"
                echo -e "  ${DIM}  go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest${RESET}"
            fi
        else
            echo -e "  ${DIM}  Skipped. Install manually: go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest${RESET}"
        fi
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

    # [1/9] Required — loop until bumblebee is confirmed present or cloned
    while true; do
        while true; do
            echo -e "  ${BOLD}[1/9] Bumblebee home directory${RESET}"
            echo -e "  ${DIM}Your local clone of the bumblebee GitHub repo ($BUMBLEBEE_REPO_URL)${RESET}"
            read -re -p "  > " BUMBLEBEE_DIR
            if [[ -n "$BUMBLEBEE_DIR" ]]; then
                BUMBLEBEE_DIR=$(_normalize_path "$BUMBLEBEE_DIR")
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

    # [2/9] Required — no default
    while true; do
        echo -e "  ${BOLD}[2/9] Scan root path${RESET}"
        case "$(uname -s)" in
            Linux)  _scan_eg="/home (all user directories), / (entire system)" ;;
            Darwin) _scan_eg="/Users (all user directories), / (entire system)" ;;
            *)      _scan_eg="/ (entire system), or a specific directory" ;;
        esac
        echo -e "  ${DIM}Root directory bumblebee will scan recursively (e.g. ${_scan_eg})${RESET}"
        read -re -p "  > " SCAN_ROOT
        if [[ -n "$SCAN_ROOT" ]]; then SCAN_ROOT=$(_normalize_path "$SCAN_ROOT"); break; fi
        echo -e "  ${RED}Path is required.${RESET}\n"
    done
    echo ""

    # [3/9] Required — validate or create directory
    echo -e "  ${BOLD}[3/9] Log directory${RESET}"
    echo -e "  ${DIM}Where scan reports will be saved. Will be created if it does not exist.${RESET}"
    echo -e "  ${DIM}Relative paths are anchored to \$HOME automatically.${RESET}"
    _set_log_dir
    echo ""

    _prompt_value "[4/9] Log retention (days)" "$DEFAULT_RETENTION_DAYS" RETENTION_DAYS

    echo -e "  ${BOLD}[5/9] Output format${RESET}  (human = dashboard, raw = NDJSON)"
    echo -e "  ${DIM}[default: human]${RESET}"
    read -re -p "  > " _fmt
    OUTPUT_FORMAT="${_fmt:-human}"
    [[ "$OUTPUT_FORMAT" != "raw" ]] && OUTPUT_FORMAT="human"
    echo ""

    echo -e "  ${BOLD}[6/9] Auto-export report after scan? [yes/no]${RESET}"
    echo -e "  ${DIM}[default: yes]${RESET}"
    read -re -p "  > " _exp
    _exp=$(echo "${_exp:-yes}" | tr '[:upper:]' '[:lower:]')
    EXPORT_REPORT=$([[ "$_exp" == "no" ]] && echo "no" || echo "yes")
    echo ""

    echo -e "  ${BOLD}[7/9] Check for bscan updates before each run? [yes/no]${RESET}"
    echo -e "  ${DIM}Offers to pull the latest bscan when your checkout is behind. [default: yes]${RESET}"
    read -re -p "  > " _sbr
    _sbr=$(echo "${_sbr:-yes}" | tr '[:upper:]' '[:lower:]')
    SYNC_BSCAN_REPO=$([[ "$_sbr" == "no" ]] && echo "no" || echo "yes")
    echo ""

    echo -e "  ${BOLD}[8/9] Sync threat catalog before each run? [yes/no]${RESET}"
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

    echo -e "  ${BOLD}[9/9] Install 'bscan' command? [yes/no]${RESET}"
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
    echo ""
    echo -e "  ${BOLD}[L]${RESET} bscan Symlink        : ${YELLOW}$(_symlink_status)${RESET}"
    echo -e "  ${BOLD}[R]${RESET} Reconfigure (delete .env, re-run wizard)"
    echo -e "  ${BOLD}[U]${RESET} Uninstall"
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
                input_val=$(_normalize_path "$input_val")
                if [[ "$(basename "$input_val")" != "bumblebee" ]]; then
                    input_val="${input_val%/}/bumblebee"
                    echo -e "${DIM}Path adjusted to: $input_val${RESET}"
                fi
                [[ ! -d "$input_val" ]] && echo -e "${YELLOW}Warning: Directory does not exist yet. Saving anyway.${RESET}"
                BUMBLEBEE_DIR="$input_val"; save_config
            fi
            ;;
        2)
            read -rp "Enter new System Scan Target Path: " input_val
            if [[ -n "$input_val" ]]; then
                input_val=$(_normalize_path "$input_val")
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
            echo -e "  ${DIM}Relative paths are anchored to \$HOME automatically.${RESET}"
            _set_log_dir
            save_config
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
        l)
            _manage_symlink
            ;;
        r)
            reconfigure
            ;;
        u)
            _run_uninstall
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

BUMBLEBEE_BIN=$(_find_bumblebee_bin 2>/dev/null || true)
if [[ -z "$BUMBLEBEE_BIN" ]]; then
    echo -e "${RED}ERROR: 'bumblebee' binary not found.${RESET}"
    echo -e "${DIM}Install via: go install github.com/perplexityai/bumblebee/cmd/bumblebee@latest${RESET}"
    echo -e "${DIM}Full instructions: $BUMBLEBEE_REPO_URL${RESET}"
    exit 1
fi

echo ""
echo -e "${CYAN}==> Launching ${BOLD}$SCAN_PROFILE${RESET}${CYAN} sweep on ${BOLD}$SCAN_ROOT${RESET}${CYAN}...${RESET}"
echo ""

SCAN_TMPFILE=$(mktemp)

if [[ "$SCAN_MODE" == "verbose" ]]; then
    set +e
    sudo "$BUMBLEBEE_BIN" scan \
      --profile "$SCAN_PROFILE" \
      --root "$SCAN_ROOT" \
      --exposure-catalog "$CATALOG_PATH" 2>&1 | tee "$SCAN_TMPFILE"
    SCAN_EXIT="${PIPESTATUS[0]}"
    set -e
else
    sudo "$BUMBLEBEE_BIN" scan \
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
