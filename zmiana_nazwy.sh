#!/bin/bash

#------------------------------------------------------------
# print help
#------------------------------------------------------------
print_help(){
    echo "============================================================"
    echo " File Renamer Tool"
    echo "============================================================"
    echo
    echo "USAGE:"
    echo "  $0 [options]"
    echo
    echo "DESCRIPTION:"
    echo "  Recursively or non-recursively scans a directory and renames"
    echo "  files based on a user-defined pattern system."
    echo
    echo "  Supports EXIF metadata (via exiftool), numbering, filename"
    echo "  manipulation, and predefined media tags."
    echo
    echo "------------------------------------------------------------"
    echo "OPTIONS:"
    echo
    echo "  -h, --help"
    echo "      Show this help message"
    echo
    echo "  -d, --directory DIR"
    echo "      Target directory to scan (default: current directory)"
    echo
    echo "  -r, --recursive"
    echo "      Scan directories recursively"
    echo
    echo "  -v, --verbose"
    echo "      Show basic progress information"
    echo
    echo "  -vv, --very-verbose"
    echo "      Show detailed file-by-file processing output"
    echo
    echo "  -f, --force"
    echo "      Actually rename files (without this, script only scans)"
    echo
    echo "  -e, --extensions LIST"
    echo "      Filter by file extensions (space-separated)"
    echo "      Example: -e jpg png mp4"
    echo
    echo "  -t, --tag TAG"
    echo "      Predefined file groups (overrides extensions):"
    echo "        music -> mp3, flac, wav, aac, ogg"
    echo "        video -> mp4, mkv, avi, mov, webm"
    echo "        image -> jpg, jpeg, png, gif, bmp, webp"
    echo
    echo "  -p, --pattern PATTERN"
    echo "      Rename pattern system using tokens:"
    echo
    echo "      TOKENS:"
    echo "        {num}        -> file counter"
    echo "        {num:04}     -> zero-padded counter (e.g. 0001)"
    echo "        {name}       -> original filename without extension"
    echo "        {ext}        -> file extension"
    echo "        {any_exif}   -> any EXIF tag via exiftool (e.g. {DateTimeOriginal})"
    echo
    echo "      EXAMPLES:"
    echo "        -p \"{num:04}_{name}\""
    echo "        -p \"{DateTimeOriginal}_{num}\""
    echo "        -p \"IMG_{num:03}.{ext}\""
    echo
    echo "  --num-mode MODE"
    echo "      Numbering behavior:"
    echo "        per-dir  -> reset counter per directory (default)"
    echo "        global   -> continuous numbering across all files"
    echo
    echo "------------------------------------------------------------"
    echo "EXAMPLES:"
    echo
    echo "  Scan images only:"
    echo "    $0 -t image -r"
    echo
    echo "  Rename photos sequentially:"
    echo "    $0 -t image -p \"IMG_{num:04}\" -f"
    echo
    echo "  Rename videos with original name preserved:"
    echo "    $0 -t video -p \"{name}_edited_{num}\" -f"
    echo
    echo "  Dry scan with verbose output:"
    echo "    $0 -r -vv"
    echo
    echo "============================================================"
    exit 0
}

#------------------------------------------------------------
# Install dependencies
#------------------------------------------------------------
install_deps() {
    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y "$@"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$@"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm "$@"
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$@"
    else
        echo "Unsupported package manager. Install manually: $*"
        exit 1
    fi
}

#------------------------------------------------------------
# Cleanup
#------------------------------------------------------------
cleanup_on_exit() {
    printf "Stopping...\n"
    kill "$spinner_pid" 2>/dev/null
    exit 0
}

#------------------------------------------------------------
# Spinner
#------------------------------------------------------------
spinner_loop() {
    local spinner_chars='/-\|'
    local spinner_index=0

    while :; do
        printf "\rProcessing... %c" "${spinner_chars:spinner_index++:1}"
        ((spinner_index == ${#spinner_chars})) && spinner_index=0
        sleep 0.1
    done
}

#------------------------------------------------------------
# Tag -> extensions
#------------------------------------------------------------
set_extensions_by_tag() {
    case "$file_tag" in
        music)
            file_extensions=("mp3" "flac" "wav" "aac" "ogg")
            ;;
        video)
            file_extensions=("mp4" "mkv" "avi" "mov" "webm")
            ;;
        image)
            file_extensions=("jpg" "jpeg" "png" "gif" "bmp" "webp")
            ;;
    esac
}

#------------------------------------------------------------
# Directory scan
#------------------------------------------------------------
scan_directory() {
    local current_dir="$1"
    local found_files=()
    local found_dirs=()

    for entry in "$current_dir"/*; do
        [ -e "$entry" ] || continue

        if [ -d "$entry" ]; then
            if [[ "$is_recursive" == true ]]; then
                found_dirs+=("$entry")
                dirs_list+=("$entry")
            fi
        else
            if [[ "$script_path" == "$entry" ]]; then
                continue
            fi

            file_ext="${entry##*.}"

            if [[ ${#file_extensions[@]} -eq 0 ]]; then
                found_files+=("$entry")
                files_list+=("$entry")
                continue
            fi

            for ext in "${file_extensions[@]}"; do
                if [[ "$file_ext" == "$ext" ]]; then
                    found_files+=("$entry")
                    files_list+=("$entry")
                    break
                fi
            done
        fi
    done

    if [[ "$is_verbose" == true || "$is_very_verbose" == true ]]; then
        printf "\nChecked directory: %s\n" "$current_dir"
        printf "Files found: %s\n" "${#found_files[@]}"
        printf "Directories found: %s\n" "${#found_dirs[@]}"
    fi

    if [[ "$is_very_verbose" == true ]]; then
        for f in "${found_files[@]}"; do
            printf "File found: %s\n" "$f"
        done
    fi

    for d in "${found_dirs[@]}"; do
        scan_directory "$d"
    done
}

#------------------------------------------------------------
# Pattern tokenization
#------------------------------------------------------------
parse_pattern_tokens() {
    local pattern="$1"
    pattern_tokens=()

    while [[ "$pattern" == *"{"*"}"* ]]; do
        local prefix="${pattern%%\{*}"
        local rest="${pattern#*\{}"
        local token="${rest%%\}*}"
        local suffix="${rest#*\}}"

        [[ -n "$prefix" ]] && pattern_tokens+=("TEXT:$prefix")
        pattern_tokens+=("TOKEN:$token")

        pattern="$suffix"
    done

    [[ -n "$pattern" ]] && pattern_tokens+=("TEXT:$pattern")
}
#------------------------------------------------------------
# Resolve token
#------------------------------------------------------------
resolve_pattern_token() {
    local token="$1"
    local file="$2"

    local key="${token%%:*}"
    local format="${token#*:}"

    [[ "$key" == "$format" ]] && format=""

    case "$key" in
        num)
            if [[ -n "$format" ]]; then
                printf "%0${format}d" "$file_counter"
            else
                echo "$file_counter"
            fi
            ;;
        ext)
            echo "${file##*.}"
            ;;
        name)
            local base="${file##*/}"
            echo "${base%.*}"
            ;;
        *)
            local value
            value=$(get_exif_value "$file" "$key")

            [[ -z "$value" ]] && value="UNKNOWN"

            echo "$value" | tr ':' '-' | tr ' ' '_' | tr -cd '[:alnum:]_.-'
            ;;
    esac
}
#------------------------------------------------------------
# helper
#------------------------------------------------------------
get_exif_value() {
    local file="$1"
    local key="$2"

    local cache_key="${file}::${key}"

    if [[ -n "${exif_cache[$cache_key]}" ]]; then
        echo "${exif_cache[$cache_key]}"
        return
    fi

    local value
    value=$(exiftool -s -s -s "-$key" "$file")

    exif_cache[$cache_key]="$value"
    echo "$value"
}
#------------------------------------------------------------
# Build filename
#------------------------------------------------------------
build_filename_from_pattern() {
    local file="$1"
    local output=""

    for part in "${pattern_tokens[@]}"; do
        type="${part%%:*}"
        value="${part#*:}"

        if [[ "$type" == "TEXT" ]]; then
            output+="$value"
        else
            resolved=$(resolve_pattern_token "$value" "$file")
            output+="$resolved"
        fi
    done

    echo "$output"
}

#------------------------------------------------------------
# Rename files
#------------------------------------------------------------
rename_files() {
    file_counter=1

    for file in "${files_list[@]}"; do
        dir="$(dirname "$file")"

        new_filename="$(build_filename_from_pattern "$file")"
        new_filepath="$dir/$new_filename"

        if [[ -e "$new_filepath" && "$file" != "$new_filepath" ]]; then
            i=1
            base="${new_filename%.*}"
            ext="${new_filename##*.}"

            while [[ -e "$dir/${base}_$i.$ext" ]]; do
                ((i++))
            done

            new_filepath="$dir/${base}_$i.$ext"
        fi

        if [[ "$is_verbose" == true || "$is_very_verbose" == true ]]; then
            printf "Renaming:\n  %s\n→ %s\n\n" "$file" "$new_filepath"
        fi

        if [[ "$is_force" == true ]]; then
            mv -- "$file" "$new_filepath"
        fi

        ((file_counter++))
    done
}

#------------------------------------------------------------
# Init
#------------------------------------------------------------
script_path="$(realpath "$0")"

files_list=()
dirs_list=()

target_dir="$(pwd)"

is_recursive=false
is_verbose=false
is_very_verbose=false
is_force=false

file_extensions=()
file_tag=""
rename_pattern=""
number_mode="per-dir"

ALLOWED_TAGS=("music" "video" "image")

#------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            ;;
        -d|--directory)
            target_dir="$2"
            shift
            ;;
        -r|--recursive)
            is_recursive=true
            ;;
        -v|--verbose)
            is_verbose=true
            ;;
        -vv|--very-verbose)
            is_very_verbose=true
            ;;
        -e|--extensions)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                file_extensions+=("$1")
                shift
            done
            continue
            ;;
        -f|--force)
            is_force=true
            ;;
        -p|--pattern)
            # check if argument exists
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --pattern requires a value"
                exit 1
            fi

            rename_pattern="$2"

            # extract tokens and validate basic format
            for token in $(grep -o '{[^}]*}' <<< "$rename_pattern" | tr -d '{}'); do
                key="${token%%:*}"

                if [[ ! "$key" =~ ^[a-zA-Z0-9_]+$ ]]; then
                    echo "Error: Invalid token '{$token}'"
                    exit 1
                fi
            done

            shift
            ;;
        -t|--tag)
            if [[ " ${ALLOWED_TAGS[*]} " == *" $2 "* ]]; then
                file_tag="$2"
                set_extensions_by_tag
            else
                echo "Error: invalid tag"
                exit 1
            fi
            shift
            ;;
        --num-mode)
            number_mode="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

#------------------------------------------------------------
# Dependencies
#------------------------------------------------------------
dependencies=(exiftool)
missing_deps=()

for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing_deps+=("$dep")
    fi
done

if [[ ${#missing_deps[@]} -ne 0 ]]; then
    echo "Installing missing dependencies..."
    install_deps "${missing_deps[@]}"
fi

#------------------------------------------------------------
# Run
#------------------------------------------------------------
if [[ -z "${rename_pattern// }" ]]; then
    echo "Error: -p|--pattern is required and cannot be empty"
    echo "Example: $0 -t image -p \"IMG_{num:04}\" -f"
    exit 1
fi

parse_pattern_tokens "$rename_pattern"

trap cleanup_on_exit SIGINT

if [[ "$is_verbose" == false ]]; then
    spinner_loop &
    spinner_pid=$!
fi

scan_directory "$target_dir"

kill "$spinner_pid" 2>/dev/null

IFS=$'\n' files_list=($(printf "%s\n" "${files_list[@]}" | sort))

printf "\nDone!\n"
printf "Files found: %s\n" "${#files_list[@]}"
printf "Directories found: %s\n" "${#dirs_list[@]}"

if [[ "$is_force" == false ]]; then
    read -p "Proceed to show how changing names will look? (y/n): " confirm
    is_very_verbose=true
    rename_files
    echo "Program finished!"
    exit 0
fi

read -p "Proceed to changing names? (y/n): " confirm
[[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]] || cleanup_on_exit

rename_files

echo "Program finished!"
exit 0
