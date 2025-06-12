#!/bin/zsh
# -----------------------------------------------------------------------------
# BTAU (Back That App Up) - v1.3.3 (2025-02-28)
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
#   Supports optional encryption (AES-256-CBC via OpenSSL with PBKDF2), adjustable compression,
#   multiple archive formats (targz, gz, zip, 7zip), splitting options, interactive prompting,
#   dry-run mode, output directory specification, and progress spinner animation.
#
#   Command-line options include:
#     --no-env     : Exclude .env files (default; include if not specified)
#     --zip-by     : Splitting mode: split [N] or split --max SIZE or sub LEVEL
#     --no-pass    : Do not use encryption (skip password prompt)
#     --comp       : Compression level (none, min, normal, maximum)
#     --format     : Archive format (targz, gz, zip, 7zip)
#     --log-level  : Log verbosity (INFO, WARN, ERROR; default: WARN) and sets YJ_CONFIG_LOGLEVEL
#     --name       : Archive name parameter (<default|custom<string>|dir>).
#                  If omitted, defaults to "btau_archive_<TIMESTAMP>.<ext>".
#     --output-dir : Directory to place the generated archive(s) (default: current directory)
#     --prompt     : Interactive prompting for parameters
#     --no-warn    : Suppress warnings
#     --dry-run    : Show commands without executing them
#
# Usage Examples:
#   ./BTAU.sh --zip-by split 3
#   ./BTAU.sh --no-env --zip-by split --max 2GB --comp maximum --format 7zip --log-level INFO --name customMyBackup --output-dir /path/to/backup
#   ./BTAU.sh --zip-by sub 1 --prompt --dry-run
#
# -----------------------------------------------------------------------------

# Splash screen
splash() {
  echo "=========================================="
  echo " BTAU (Back That App Up) v1.3.3 (2025-02-28)"
  echo " Developed by:"
  echo "  - Jeremiah Pegues (jeremiah@pegues.io) - https://pegues.io"
  echo "  - OPSGAÃNG Sistemi (word@iite.bet) - https://iite.bet/ardela/schemas"
  echo "=========================================="
}
splash

# ANSI color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set strict error handling
set -euo pipefail
trap 'echo -e "${RED}[ERROR] An unexpected error occurred on line ${LINENO}. Exiting.${NC}"; exit 1' ERR

# Default parameters:
NO_ENV=false
ZIP_BY_MODE="none"
SPLIT_COUNT=0
SPLIT_MAX=""
SUB_LEVEL=0
NO_PASS=true
COMP_LEVEL="normal"
FORMAT="targz"
LOG_LEVEL="WARN"
PROMPT=false
NO_WARN=false
DRY_RUN=false
ARCHIVE_NAME_PARAM="default"
OUTPUT_DIR="."  # default output directory is current directory

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --no-env)
            NO_ENV=true; shift ;;
        --zip-by)
            shift
            if [[ "$1" == "split" ]]; then
                ZIP_BY_MODE="split"; shift
                if [[ "$1" == "--max" ]]; then
                    shift; SPLIT_MAX="$1"; shift
                else
                    SPLIT_COUNT="$1"; shift
                fi
            elif [[ "$1" == "sub" ]]; then
                ZIP_BY_MODE="sub"; shift; SUB_LEVEL="$1"; shift
            else
                echo -e "${RED}Invalid --zip-by option${NC}"; exit 1
            fi ;;
        --no-pass)
            NO_PASS=true; shift ;;
        --comp)
            shift; case "$1" in
                none|min|normal|maximum) COMP_LEVEL="$1"; shift ;;
                *) echo -e "${RED}Invalid compression level. Choose: none, min, normal, maximum.${NC}"; exit 1 ;;
            esac ;;
        --format)
            shift; case "$1" in
                targz|gz|zip|7zip) FORMAT="$1"; shift ;;
                *) echo -e "${RED}Invalid format. Choose: targz, gz, zip, 7zip.${NC}"; exit 1 ;;
            esac ;;
        --log-level)
            shift; case "$1" in
                INFO|WARN|ERROR) LOG_LEVEL="$1"; export YJ_CONFIG_LOGLEVEL="$LOG_LEVEL"; shift ;;
                *) echo -e "${RED}Invalid log level. Choose: INFO, WARN, ERROR.${NC}"; exit 1 ;;
            esac ;;
        --name)
            shift; ARCHIVE_NAME_PARAM="$1"; shift ;;
        --output-dir)
            shift; OUTPUT_DIR="$1"; shift ;;
        --prompt)
            PROMPT=true; shift ;;
        --no-warn)
            NO_WARN=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# Ensure the output directory exists
if [[ ! -d "$OUTPUT_DIR" ]]; then
    echo -e "${YELLOW}[INFO] Creating output directory: $OUTPUT_DIR${NC}"
    mkdir -p "$OUTPUT_DIR"
fi

# Interactive prompting if --prompt is set
if [ "$PROMPT" = true ]; then
    read -q "answer?Exclude .env files? (y/n, default y): "
    echo
    if [[ "$answer" =~ ^[Nn] ]]; then NO_ENV=false; else NO_ENV=true; fi
    read "fmt?Archive format (targz, gz, zip, 7zip) [default targz]: "
    if [ -n "$fmt" ]; then FORMAT="$fmt"; fi
    read "comp?Compression level (none, min, normal, maximum) [default normal]: "
    if [ -n "$comp" ]; then COMP_LEVEL="$comp"; fi
    read -q "enc?Use encryption? (y/n, default y): "
    echo
    if [[ "$enc" =~ ^[Nn] ]]; then NO_PASS=true; else NO_PASS=false; fi
    read "lvl?Log level (INFO, WARN, ERROR) [default WARN]: "
    if [ -n "$lvl" ]; then LOG_LEVEL="$lvl"; export YJ_CONFIG_LOGLEVEL="$LOG_LEVEL"; fi
    read "name?Archive name parameter (default, dir, or custom<string>) [default default]: "
    if [ -n "$name" ]; then ARCHIVE_NAME_PARAM="$name"; fi
    read "out?Output directory [default current directory]: "
    if [ -n "$out" ]; then OUTPUT_DIR="$out"; [[ ! -d "$OUTPUT_DIR" ]] && mkdir -p "$OUTPUT_DIR"; fi
fi

# Setup logging function with colors
log_msg() {
    local level="$1"
    local msg="$2"
    typeset -A LEVELS
    LEVELS=( INFO 1 WARN 2 ERROR 3 )
    if [ "${LEVELS[$level]}" -lt "${LEVELS[$LOG_LEVEL]}" ]; then return; fi
    case $level in
      INFO) local color="${BLUE}" ;;
      WARN) local color="${YELLOW}" ;;
      ERROR) local color="${RED}" ;;
      *) local color="${NC}" ;;
    esac
    logger -t BTAU "[$level] $msg"
    echo -e "${color}[$level]${NC} $msg"
}

if [ "$NO_WARN" = true ]; then exec 2>/dev/null; fi

# Spinner function
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Enhanced run_cmd to use spinner
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        log_msg "INFO" "DRY-RUN: $*"
    else
        log_msg "INFO" "Running: $*"
        # Run command in background
        eval "$*" &
        cmd_pid=$!
        spinner $cmd_pid
        wait $cmd_pid
    fi
}

log_msg "INFO" "Starting BTAU with parameters: NO_ENV=$NO_ENV, ZIP_BY_MODE=$ZIP_BY_MODE, NO_PASS=$NO_PASS, COMP_LEVEL=$COMP_LEVEL, FORMAT=$FORMAT, ARCHIVE_NAME_PARAM=$ARCHIVE_NAME_PARAM, OUTPUT_DIR=$OUTPUT_DIR, LOG_LEVEL=$LOG_LEVEL, PROMPT=$PROMPT, NO_WARN=$NO_WARN, DRY_RUN=$DRY_RUN"

# Build exclusion patterns for tar (EXCLUDES) and for find (FIND_EXCLUDES)
EXCLUDES=()
FIND_EXCLUDES=()
if [ "$NO_ENV" = false ]; then
    EXCLUDES+=("--exclude=.env")
    FIND_EXCLUDES+=(".env")
fi

for item in .git node_modules venv __pycache__ .cache; do
    EXCLUDES+=("--exclude=$item")
    FIND_EXCLUDES+=("$item")
done

if [ -f .gitignore ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        EXCLUDES+=("--exclude=$line")
        FIND_EXCLUDES+=("$line")
    done < .gitignore
fi

for item in vendor log tmp .bundle Gemfile.lock deps _build packages obj bin target build out; do
    EXCLUDES+=("--exclude=$item")
    FIND_EXCLUDES+=("$item")
done

for item in .DS_Store .AppleDouble .LSOverride; do
    EXCLUDES+=("--exclude=$item")
    FIND_EXCLUDES+=("$item")
done

for item in Thumbs.db desktop.ini; do
    EXCLUDES+=("--exclude=$item")
    FIND_EXCLUDES+=("$item")
done

# Create a temporary file list using find with an array (avoiding glob expansion issues)
FILELIST=$(mktemp)
FIND_ARGS=(. -type f)
for pat in "${FIND_EXCLUDES[@]}"; do
    FIND_ARGS+=(-not -path "./$pat")
done
find "${FIND_ARGS[@]}" > "$FILELIST"
log_msg "INFO" "File list created using find with arguments: ${FIND_ARGS[*]}"

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

case "$COMP_LEVEL" in
    none) GZIP_OPT="-0" ;;
    min) GZIP_OPT="-1" ;;
    normal) GZIP_OPT="-6" ;;
    maximum) GZIP_OPT="-9" ;;
esac
log_msg "INFO" "Compression level: $COMP_LEVEL ($GZIP_OPT)"

OS_TYPE=$(uname)
if [[ "$OS_TYPE" == "Darwin" ]]; then
    STAT_CMD="stat -f%z"
else
    STAT_CMD="stat -c%s"
fi

# Generate archive prefix based on --name parameter
if [[ "$ARCHIVE_NAME_PARAM" == "default" ]]; then
    ARCHIVE_PREFIX="btau_archive_"
elif [[ "$ARCHIVE_NAME_PARAM" == "dir" ]]; then
    ARCHIVE_PREFIX="$(basename "$PWD")_"
elif [[ "$ARCHIVE_NAME_PARAM" == custom* ]]; then
    ARCHIVE_PREFIX="${ARCHIVE_NAME_PARAM#custom}_"
else
    ARCHIVE_PREFIX="${ARCHIVE_NAME_PARAM}_"
fi

TIMESTAMP=$(date +%Y%m%d%H%M%S)
ARCHIVE_BASE="${ARCHIVE_PREFIX}${TIMESTAMP}"
ARCHIVE_NAME=""
case "$FORMAT" in
    targz|gz) ARCHIVE_NAME="${OUTPUT_DIR}/${ARCHIVE_BASE}.tar.gz" ;;
    zip) ARCHIVE_NAME="${OUTPUT_DIR}/${ARCHIVE_BASE}.zip" ;;
    7zip) ARCHIVE_NAME="${OUTPUT_DIR}/${ARCHIVE_BASE}.7z" ;;
esac

log_msg "INFO" "Archive will be named: $ARCHIVE_NAME"

create_archive() {
    if [[ "$FORMAT" == "targz" || "$FORMAT" == "gz" ]]; then
        TAR_CMD="tar -czf - ${EXCLUDES[@]} -T \"$FILELIST\""
        if [ "$NO_PASS" = false ]; then
            CMD="$TAR_CMD | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:\"$PASSWORD\" -out \"$ARCHIVE_NAME\""
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
        SUB_ARCHIVE_BASE="${archive_label}_$TIMESTAMP"
        case "$FORMAT" in
            targz|gz) SUB_ARCHIVE="${OUTPUT_DIR}/${SUB_ARCHIVE_BASE}.tar.gz" ;;
            zip) SUB_ARCHIVE="${OUTPUT_DIR}/${SUB_ARCHIVE_BASE}.zip" ;;
            7zip) SUB_ARCHIVE="${OUTPUT_DIR}/${SUB_ARCHIVE_BASE}.7z" ;;
        esac
        TEMP_FILELIST=$(mktemp)
        find "$subdir" -type f $(for pattern in "${FIND_EXCLUDES[@]}"; do echo -n " -not -path \"./$pattern\""; done) > "$TEMP_FILELIST"
        if [[ "$FORMAT" == "targz" || "$FORMAT" == "gz" ]]; then
            TAR_CMD="tar -czf - ${EXCLUDES[@]} -T \"$TEMP_FILELIST\""
            if [ "$NO_PASS" = false ]; then
                SUB_CMD="$TAR_CMD | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:\"$PASSWORD\" -out \"$SUB_ARCHIVE\""
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