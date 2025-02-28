#!/bin/zsh
# -----------------------------------------------------------------------------
# BTAU (Back That App Up) - v1.1.0 (2025-02-28)
#
# Authors:
#   - Jeremiah Pegues <jeremiah@pegues.io> - https://pegues.io
#   - OPSGAÃNG Sistemi <word@iite.bet> - https://iite.bet/ardela/schemas
#
# Description:
#   Archives directories recursively while excluding files and directories
#   based on .gitignore, hidden dirs, system cache files, language-specific
#   directories (e.g. node_modules, venv, vendor, deps, etc.), and OS system files.
#
#   Supports optional encryption (AES-256-CBC via OpenSSL), adjustable compression,
#   multiple archive formats (targz, gz, zip, 7zip), splitting options, and verbose logging.
#
#   Command-line options:
#
#     --no-env     : Include .env files rather than excluding them (default: exclude)
#     --zip-by     : Specify splitting mode:
#                     split [N] or split --max SIZE or sub LEVEL
#     --no-pass    : Do not use encryption (skip password prompt)
#     --comp       : Compression level (none, min, normal, maximum)
#     --format     : Archive format (targz, gz, zip, 7zip)
#     --log-level  : Log verbosity (INFO, WARN, ERROR; default: WARN) and sets YJ_CONFIG_LOGLEVEL
#     --prompt     : Interactive prompting of parameters
#     --no-warn    : Suppress warnings
#     --dry-run    : Perform a dry run without executing commands
#
# Usage Examples:
#   ./BTAU.sh --zip-by split 3
#   ./BTAU.sh --no-env --zip-by split --max 2GB --comp maximum --format 7zip --log-level INFO
#   ./BTAU.sh --zip-by sub 1 --prompt --dry-run
#
# -----------------------------------------------------------------------------

# Splash screen
splash() {
  echo "=========================================="
  echo " BTAU (Back That App Up) v1.1.0 (2025-02-28)"
  echo " Developed by:"
  echo "  - Jeremiah Pegues (jeremiah@pegues.io) - https://pegues.io"
  echo "  - OPSGAÃNG Sistemi (word@iite.bet) - https://iite.bet/ardela/schemas"
  echo "=========================================="
}
splash

# Set strict error handling
set -euo pipefail

# Trap errors and print a message before exiting
trap 'echo "[ERROR] An unexpected error occurred on line ${LINENO}. Exiting."; exit 1' ERR

# Default parameters:
NO_ENV=false
ZIP_BY_MODE="none"
SPLIT_COUNT=0
SPLIT_MAX=""
SUB_LEVEL=0
NO_PASS=false
COMP_LEVEL="normal"
FORMAT="targz"
LOG_LEVEL="WARN"
PROMPT=false
NO_WARN=false
DRY_RUN=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --no-env)
            NO_ENV=true
            shift
            ;;
        --zip-by)
            shift
            if [[ "$1" == "split" ]]; then
                ZIP_BY_MODE="split"
                shift
                if [[ "$1" == "--max" ]]; then
                    shift
                    SPLIT_MAX="$1"
                    shift
                else
                    SPLIT_COUNT="$1"
                    shift
                fi
            elif [[ "$1" == "sub" ]]; then
                ZIP_BY_MODE="sub"
                shift
                SUB_LEVEL="$1"
                shift
            else
                echo "Invalid --zip-by option"
                exit 1
            fi
            ;;
        --no-pass)
            NO_PASS=true
            shift
            ;;
        --comp)
            shift
            case "$1" in
                none|min|normal|maximum)
                    COMP_LEVEL="$1"
                    shift
                    ;;
                *)
                    echo "Invalid compression level. Choose: none, min, normal, maximum."
                    exit 1
                    ;;
            esac
            ;;
        --format)
            shift
            case "$1" in
                targz|gz|zip|7zip)
                    FORMAT="$1"
                    shift
                    ;;
                *)
                    echo "Invalid format. Choose: targz, gz, zip, 7zip."
                    exit 1
                    ;;
            esac
            ;;
        --log-level)
            shift
            case "$1" in
                INFO|WARN|ERROR)
                    LOG_LEVEL="$1"
                    export YJ_CONFIG_LOGLEVEL="$LOG_LEVEL"
                    shift
                    ;;
                *)
                    echo "Invalid log level. Choose: INFO, WARN, ERROR."
                    exit 1
                    ;;
            esac
            ;;
        --prompt)
            PROMPT=true
            shift
            ;;
        --no-warn)
            NO_WARN=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Interactive prompting if --prompt is set
if [ "$PROMPT" = true ]; then
    read -q "answer?Exclude .env files? (y/n, default y): "
    echo
    if [[ "$answer" =~ ^[Nn] ]]; then
        NO_ENV=false
    else
        NO_ENV=true
    fi

    read "fmt?Archive format (targz, gz, zip, 7zip) [default targz]: "
    if [ -n "$fmt" ]; then
        FORMAT="$fmt"
    fi

    read "comp?Compression level (none, min, normal, maximum) [default normal]: "
    if [ -n "$comp" ]; then
        COMP_LEVEL="$comp"
    fi

    read -q "enc?Use encryption? (y/n, default y): "
    echo
    if [[ "$enc" =~ ^[Nn] ]]; then
        NO_PASS=true
    else
        NO_PASS=false
    fi

    read "lvl?Log level (INFO, WARN, ERROR) [default WARN]: "
    if [ -n "$lvl" ]; then
        LOG_LEVEL="$lvl"
        export YJ_CONFIG_LOGLEVEL="$LOG_LEVEL"
    fi
fi

# Setup logging function (syslog style)
log_msg() {
    local level="$1"
    local msg="$2"
    # Define levels: INFO (1), WARN (2), ERROR (3)
    typeset -A LEVELS
    LEVELS=( INFO 1 WARN 2 ERROR 3 )
    if [ "${LEVELS[$level]}" -lt "${LEVELS[$LOG_LEVEL]}" ]; then
        return
    fi
    logger -t BTAU "[$level] $msg"
    echo "[$level] $msg"
}

if [ "$NO_WARN" = true ]; then
    exec 2>/dev/null
fi

# Function to run commands; in dry-run mode, just echo them.
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        log_msg "INFO" "DRY-RUN: $*"
    else
        log_msg "INFO" "Running: $*"
        eval "$*"
    fi
}

log_msg "INFO" "Starting BTAU with parameters: NO_ENV=$NO_ENV, ZIP_BY_MODE=$ZIP_BY_MODE, NO_PASS=$NO_PASS, COMP_LEVEL=$COMP_LEVEL, FORMAT=$FORMAT, LOG_LEVEL=$LOG_LEVEL, PROMPT=$PROMPT, NO_WARN=$NO_WARN, DRY_RUN=$DRY_RUN"

# Build exclusion patterns
EXCLUDES=()
if [ "$NO_ENV" = false ]; then
    EXCLUDES+=("--exclude=.env")
fi

# General exclusions
EXCLUDES+=("--exclude=.git")
EXCLUDES+=("--exclude=node_modules")
EXCLUDES+=("--exclude=venv")
EXCLUDES+=("--exclude=__pycache__")
EXCLUDES+=("--exclude=.cache")
EXCLUDES+=("--exclude=*/.*")

# Exclusions from .gitignore
if [ -f .gitignore ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        EXCLUDES+=("--exclude=$line")
    done < .gitignore
fi

# Additional exclusions for Ruby, Elixir, PowerShell, etc.
EXCLUDES+=("--exclude=vendor")
EXCLUDES+=("--exclude=log")
EXCLUDES+=("--exclude=tmp")
EXCLUDES+=("--exclude=.bundle")
EXCLUDES+=("--exclude=Gemfile.lock")
EXCLUDES+=("--exclude=deps")
EXCLUDES+=("--exclude=_build")
EXCLUDES+=("--exclude=packages")
EXCLUDES+=("--exclude=obj")
EXCLUDES+=("--exclude=bin")
EXCLUDES+=("--exclude=target")
EXCLUDES+=("--exclude=build")
EXCLUDES+=("--exclude=out")
# macOS system files
EXCLUDES+=("--exclude=.DS_Store")
EXCLUDES+=("--exclude=.AppleDouble")
EXCLUDES+=("--exclude=.LSOverride")
# Windows system files
EXCLUDES+=("--exclude=Thumbs.db")
EXCLUDES+=("--exclude=desktop.ini")

# Create a temporary file list using find
FILELIST=$(mktemp)
FIND_CMD="find . -type f"
for pattern in "${EXCLUDES[@]}"; do
    FIND_CMD+=" -not -path \"./$pattern\""
done
eval "$FIND_CMD" > "$FILELIST"
log_msg "INFO" "File list created using command: $FIND_CMD"

# If encryption is enabled, prompt for password
if [ "$NO_PASS" = false ]; then
    read -s "PASSWORD?Enter encryption password: "
    echo
    read -s "PASSWORD_CONFIRM?Confirm encryption password: "
    echo
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        log_msg "ERROR" "Passwords do not match!"
        exit 1
    fi
else
    log_msg "WARN" "Encryption disabled (--no-pass enabled)"
fi

# Map compression level to options for gzip/zip/7zip
case "$COMP_LEVEL" in
    none) GZIP_OPT="-0" ;;
    min) GZIP_OPT="-1" ;;
    normal) GZIP_OPT="-6" ;;
    maximum) GZIP_OPT="-9" ;;
esac
log_msg "INFO" "Compression level: $COMP_LEVEL ($GZIP_OPT)"

# Determine OS for file size commands (macOS vs Linux)
OS_TYPE=$(uname)
if [[ "$OS_TYPE" == "Darwin" ]]; then
    STAT_CMD="stat -f%z"
else
    STAT_CMD="stat -c%s"
fi

# Generate archive name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ARCHIVE_BASE="archive_$TIMESTAMP"
ARCHIVE_NAME=""
case "$FORMAT" in
    targz|gz) ARCHIVE_NAME="${ARCHIVE_BASE}.tar.gz" ;;
    zip) ARCHIVE_NAME="${ARCHIVE_BASE}.zip" ;;
    7zip) ARCHIVE_NAME="${ARCHIVE_BASE}.7z" ;;
esac

# Function to create the archive
create_archive() {
    if [[ "$FORMAT" == "targz" || "$FORMAT" == "gz" ]]; then
        TAR_CMD="tar -czf - ${EXCLUDES[@]} -T \"$FILELIST\""
        if [ "$NO_PASS" = false ]; then
            CMD="$TAR_CMD | openssl enc -aes-256-cbc -salt -pass pass:\"$PASSWORD\" -out \"$ARCHIVE_NAME\""
        else
            CMD="$TAR_CMD > \"$ARCHIVE_NAME\""
        fi
    elif [[ "$FORMAT" == "zip" ]]; then
        case "$COMP_LEVEL" in
            none) ZIP_LEVEL="-0" ;;
            min) ZIP_LEVEL="-1" ;;
            normal) ZIP_LEVEL="-6" ;;
            maximum) ZIP_LEVEL="-9" ;;
        esac
        if [ "$NO_PASS" = false ]; then
            CMD="zip -r $ZIP_LEVEL -e \"$ARCHIVE_NAME\" ."
        else
            CMD="zip -r $ZIP_LEVEL \"$ARCHIVE_NAME\" ."
        fi
    elif [[ "$FORMAT" == "7zip" ]]; then
        case "$COMP_LEVEL" in
            none) SEVEN_LEVEL="-mx=0" ;;
            min) SEVEN_LEVEL="-mx=1" ;;
            normal) SEVEN_LEVEL="-mx=6" ;;
            maximum) SEVEN_LEVEL="-mx=9" ;;
        esac
        if [ "$NO_PASS" = false ]; then
            CMD="7z a $SEVEN_LEVEL -p\"$PASSWORD\" \"$ARCHIVE_NAME\" @\"$FILELIST\""
        else
            CMD="7z a $SEVEN_LEVEL \"$ARCHIVE_NAME\" @\"$FILELIST\""
        fi
    fi
    log_msg "INFO" "Archive command: $CMD"
    run_cmd "$CMD"
}

create_archive

# Handle splitting if --zip-by was specified
if [[ "$ZIP_BY_MODE" == "split" ]]; then
    if [ -n "$SPLIT_MAX" ]; then
        log_msg "INFO" "Splitting archive into chunks with maximum size: $SPLIT_MAX"
        run_cmd "split -b \"$SPLIT_MAX\" \"$ARCHIVE_NAME\" \"${ARCHIVE_NAME}_part_\""
    elif [ "$SPLIT_COUNT" -gt 0 ]; then
        FILESIZE=$(eval $STAT_CMD "\"$ARCHIVE_NAME\"")
        PART_SIZE=$(( (FILESIZE + SPLIT_COUNT - 1) / SPLIT_COUNT ))
        log_msg "INFO" "Splitting archive into $SPLIT_COUNT parts (each approx. $PART_SIZE bytes)"
        run_cmd "split -b \"$PART_SIZE\" \"$ARCHIVE_NAME\" \"${ARCHIVE_NAME}_part_\""
    fi
elif [[ "$ZIP_BY_MODE" == "sub" ]]; then
    log_msg "INFO" "Creating separate archives for each subdirectory at level $SUB_LEVEL"
    while IFS= read -r subdir; do
        archive_label=$(echo "$subdir" | sed 's#^\./##; s#/#_#g')
        SUB_ARCHIVE="${archive_label}_$TIMESTAMP"
        case "$FORMAT" in
            targz|gz) SUB_ARCHIVE="${SUB_ARCHIVE}.tar.gz" ;;
            zip) SUB_ARCHIVE="${SUB_ARCHIVE}.zip" ;;
            7zip) SUB_ARCHIVE="${SUB_ARCHIVE}.7z" ;;
        esac
        TEMP_FILELIST=$(mktemp)
        find "$subdir" -type f $(for pattern in "${EXCLUDES[@]}"; do echo -n " -not -path \"$subdir/$pattern\""; done) > "$TEMP_FILELIST"
        if [[ "$FORMAT" == "targz" || "$FORMAT" == "gz" ]]; then
            TAR_CMD="tar -czf - ${EXCLUDES[@]} -T \"$TEMP_FILELIST\""
            if [ "$NO_PASS" = false ]; then
                SUB_CMD="$TAR_CMD | openssl enc -aes-256-cbc -salt -pass pass:\"$PASSWORD\" -out \"$SUB_ARCHIVE\""
            else
                SUB_CMD="$TAR_CMD > \"$SUB_ARCHIVE\""
            fi
        elif [[ "$FORMAT" == "zip" ]]; then
            case "$COMP_LEVEL" in
                none) ZIP_LEVEL="-0" ;;
                min) ZIP_LEVEL="-1" ;;
                normal) ZIP_LEVEL="-6" ;;
                maximum) ZIP_LEVEL="-9" ;;
            esac
            if [ "$NO_PASS" = false ]; then
                SUB_CMD="zip -r $ZIP_LEVEL -e \"$SUB_ARCHIVE\" ."
            else
                SUB_CMD="zip -r $ZIP_LEVEL \"$SUB_ARCHIVE\" ."
            fi
        elif [[ "$FORMAT" == "7zip" ]]; then
            case "$COMP_LEVEL" in
                none) SEVEN_LEVEL="-mx=0" ;;
                min) SEVEN_LEVEL="-mx=1" ;;
                normal) SEVEN_LEVEL="-mx=6" ;;
                maximum) SEVEN_LEVEL="-mx=9" ;;
            esac
            if [ "$NO_PASS" = false ]; then
                SUB_CMD="7z a $SEVEN_LEVEL -p\"$PASSWORD\" \"$SUB_ARCHIVE\" @\"$TEMP_FILELIST\""
            else
                SUB_CMD="7z a $SEVEN_LEVEL \"$SUB_ARCHIVE\" @\"$TEMP_FILELIST\""
            fi
        fi
        log_msg "INFO" "Subdirectory archive command for $subdir: $SUB_CMD"
        run_cmd "$SUB_CMD"
        rm "$TEMP_FILELIST"
        log_msg "INFO" "Created archive for $subdir: $SUB_ARCHIVE"
    done < <(find . -mindepth "$SUB_LEVEL" -maxdepth "$SUB_LEVEL" -type d)
fi

log_msg "INFO" "Archive created: $ARCHIVE_NAME"
if [[ "$ZIP_BY_MODE" == "split" ]]; then
    log_msg "INFO" "Archive split into parts with prefix: ${ARCHIVE_NAME}_part_"
fi
if [[ "$ZIP_BY_MODE" == "sub" ]]; then
    log_msg "INFO" "Archives created for each subdirectory at level $SUB_LEVEL"
fi