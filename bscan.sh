#!/usr/bin/env bash

# Exit immediately if a critical command fails, except during interactive prompts
set -e

# --- Persistent Configuration File Setup ---
CONFIG_FILE="$HOME/.bumblebee_scan_config"

# Default fallback configurations
DEFAULT_BUMBLEBEE_DIR="$HOME/bumblebee"
DEFAULT_SCAN_ROOT="/Users"
DEFAULT_OUTPUT_FORMAT="human"
DEFAULT_EXPORT_REPORT="yes"
DEFAULT_LOG_DIR="$HOME/_scripts/LOGS"
DEFAULT_RETENTION_DAYS="180"

# Function to load current settings
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    # Apply defaults if variables are not yet defined
    BUMBLEBEE_DIR="${BUMBLEBEE_DIR:-$DEFAULT_BUMBLEBEE_DIR}"
    SCAN_ROOT="${SCAN_ROOT:-$DEFAULT_SCAN_ROOT}"
    OUTPUT_FORMAT="${OUTPUT_FORMAT:-$DEFAULT_OUTPUT_FORMAT}"
    EXPORT_REPORT="${EXPORT_REPORT:-$DEFAULT_EXPORT_REPORT}"
    LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
    RETENTION_DAYS="${RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"
}

# Function to write configuration changes instantly
save_config() {
    cat << EOF > "$CONFIG_FILE"
BUMBLEBEE_DIR="$BUMBLEBEE_DIR"
SCAN_ROOT="$SCAN_ROOT"
OUTPUT_FORMAT="$OUTPUT_FORMAT"
EXPORT_REPORT="$EXPORT_REPORT"
LOG_DIR="$LOG_DIR"
RETENTION_DAYS="$RETENTION_DAYS"
EOF
}

load_config

# --- Main Configuration Control Panel ---
while true; do
    clear
    echo "========================================================="
    echo "       BUMBLEBEE SCANNER CONFIGURATION CONTROL PANEL     "
    echo "========================================================="
    echo "  [1] Bumblebee Home Dir   : $BUMBLEBEE_DIR"
    echo "  [2] System Scan Target   : $SCAN_ROOT"
    echo "  [3] Target Output Format : $OUTPUT_FORMAT"
    echo "  [4] Auto-Export Report   : $EXPORT_REPORT"
    echo "  [5] Log Directory Path   : $LOG_DIR"
    echo "  [6] Log Retention Rules  : Delete logs older than $RETENTION_DAYS days"
    echo "---------------------------------------------------------"
    echo "  [P] PROCEED TO RUN SCAN  |  [Q] QUIT PROGRAM"
    echo "========================================================="
    echo ""
    read -p "Select an option to change, [P] to run, or [Q] to quit: " main_choice
    main_choice=$(echo "$main_choice" | tr '[:upper:]' '[:lower:]')

    case "$main_choice" in
        1)
            read -p "Enter new Bumblebee Directory Path: " input_val
            if [[ ! -z "$input_val" ]]; then BUMBLEBEE_DIR="$input_val"; save_config; fi
            ;;
        2)
            read -p "Enter new System Scan Target Path: " input_val
            if [[ ! -z "$input_val" ]]; then SCAN_ROOT="$input_val"; save_config; fi
            ;;
        3)
            echo "  Select Output Format:"
            echo "    1) human (Clean Visual Dashboard)"
            echo "    2) raw   (Original NDJSON Objects)"
            read -p "Choose format [1-2]: " fmt_val
            if [[ "$fmt_val" == "2" ]]; then OUTPUT_FORMAT="raw"; else OUTPUT_FORMAT="human"; fi
            save_config
            ;;
        4)
            read -p "Enable automatic log exports? [yes/no]: " input_val
            input_val=$(echo "$input_val" | tr '[:upper:]' '[:lower:]')
            if [[ "$input_val" == "yes" || "$input_val" == "no" ]]; then EXPORT_REPORT="$input_val"; save_config; fi
            ;;
        5)
            read -p "Enter new Log Directory Path: " input_val
            if [[ ! -z "$input_val" ]]; then LOG_DIR="$input_val"; save_config; fi
            ;;
        6)
            read -p "Enter number of days to retain logs (e.g., 180): " input_val
            if [[ "$input_val" =~ ^[0-9]+$ ]]; then RETENTION_DAYS="$input_val"; save_config; fi
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

# --- 2. Interactive Profile Selection Menu ---
echo ""
echo "Select Bumblebee Scan Profile:"
echo "  1) Baseline          (Quick global packages/extensions checklist)"
echo "  2) Project           (Targeted workspace/lockfile inspection)"
echo "  3) Deep [DEFAULT]    (Aggressive cross-user ecosystem sweep)"
echo "  4) Incident Response (Targeted emergency vulnerability triage)"
echo ""
read -p "Choose a profile [1-4, Default: 3]: " profile_choice

case "$profile_choice" in
    1) SCAN_PROFILE="baseline" ;;
    2) SCAN_PROFILE="project" ;;
    4) SCAN_PROFILE="incident-response" ;;
    *) SCAN_PROFILE="deep" ;;
esac

echo ""
echo "Selected Profile: $SCAN_PROFILE"
read -p "Confirm launching '$SCAN_PROFILE' scan on '$SCAN_ROOT'? [Y/n]: " final_confirm
final_confirm=$(echo "$final_confirm" | tr '[:upper:]' '[:lower:]')

if [[ ! -z "$final_confirm" && "$final_confirm" != "y" && "$final_confirm" != "yes" ]]; then
    echo "Scan canceled."
    exit 0
fi

# --- 3. Repository Sync ---
echo ""
echo "==> Updating Threat Catalogs..."
if [ -d "$BUMBLEBEE_DIR" ]; then
    cd "$BUMBLEBEE_DIR"
    echo "    Pulling latest signatures..."
    git pull
    cd - > /dev/null
else
    echo "ERROR: Core directory missing at $BUMBLEBEE_DIR"
    exit 1
fi

if [ ! -d "$CATALOG_PATH" ]; then
    echo "ERROR: Threat catalog missing at $CATALOG_PATH"
    exit 1
fi

# --- 4. Log Housekeeping & Retention Maintenance ---
if [ -d "$LOG_DIR" ]; then
    echo "==> Performing Log Purge Housekeeping (Deleting entries older than $RETENTION_DAYS days)..."
    find "$LOG_DIR" -type f -name "*.txt" -mtime +"$RETENTION_DAYS" -exec rm -f {} \;
    find "$LOG_DIR" -type f -name "*.ndjson" -mtime +"$RETENTION_DAYS" -exec rm -f {} \;
fi

# --- 5. Scan Execution ---
echo ""
echo "==> Launching $SCAN_PROFILE sweep..."
echo "    [Evaluating local code repositories against signatures...]"
echo ""

RAW_OUTPUT=$(sudo bumblebee scan \
  --profile "$SCAN_PROFILE" \
  --root "$SCAN_ROOT" \
  --exposure-catalog "$CATALOG_PATH")

# --- 6. Formatter and Engine Pipeline ---
# Generate Human-Readable Structure
HUMAN_DASHBOARD=$(cat << EOF
========================================================
               BUMBLEBEE SCAN REPORT                     
========================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Target   : $SCAN_ROOT | Profile: $SCAN_PROFILE
--------------------------------------------------------
⚠️  MALICIOUS COMPROMISES / FINDINGS DETECTED:
--------------------------------------------------------
$(echo "$RAW_OUTPUT" | awk -F'"' '/"record_type":"finding"/{
    name=""; version=""; ecosystem=""; path="";
    for(i=1;i<=NF;i++){
        if($i=="name") name=$(i+2);
        if($i=="version") version=$(i+2);
        if($i=="ecosystem") ecosystem=$(i+2);
        if($i=="path") path=$(i+2);
    }
    printf "  • [%s] %s (v%s) found at: %s\n", toupper(ecosystem), name, version, path
}' | sed 's/\\//g')
$(if ! echo "$RAW_OUTPUT" | grep -q '"record_type":"finding"'; then echo "  🟢 Clear! No known threat catalog compromises detected."; fi)

📊 SCAN PERFORMANCE METRICS:
--------------------------------------------------------
$(echo "$RAW_OUTPUT" | awk -F',' '/"record_type":"scan_summary"/{
    for(i=1;i<=NF;i++){
        if($i~/"files_considered"/) print "  Files Audited      : " \$i;
        if($i~/"package_records_suppressed"/) print "  Packages Checked   : " \$i;
        if($i~/"duration_ms"/) print "  Scan Engine Time   : " \$i " ms";
        if($i~/"status"/) print "  Engine Status      : " \$i;
    }
}' | sed -E 's/"//g' | sed -E 's/[{}]//g' | sed -E 's/^[[:space:]]+//' | sed 's/^/  /')
========================================================
EOF
)

# Render output directly to console based on user choice
if [[ "$OUTPUT_FORMAT" == "raw" ]]; then
    echo "$RAW_OUTPUT"
else
    echo "$HUMAN_DASHBOARD"
fi

# --- 7. Automated Export Generation Engine ---
if [[ "$EXPORT_REPORT" == "yes" ]]; then
    mkdir -p "$LOG_DIR"
    TIMESTAMP=$(date '+%Y_%m_%D' | tr '/' '_')
    
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
    echo "💾 Report successfully archived to: $EXPORT_TARGET"
fi

echo ""
echo "==> Execution complete."

