#!/bin/bash

#------------------------------------------------------------
# HELP
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
    echo "  Safely scans and previews file renaming before applying changes."
    echo "  You MUST use -f to actually rename files."
    echo
    echo "OPTIONS:"
    echo
    echo "  -h, --help              Show this help"
    echo "  -d, --directory DIR     Target directory (default: current)"
    echo "  -r, --recursive         Scan recursively"
    echo "  -v, --verbose           Show progress"
    echo "  -vv, --very-verbose     Detailed output"
    echo "  -f, --force             APPLY renaming (otherwise preview only)"
    echo
    echo "  -e, --extensions LIST   Filter extensions (space separated)"
    echo "  -t, --tag TAG           Predefined groups (overrides extension):"
    echo "        music -> mp3 flac wav aac ogg m4a"
    echo "        video -> mp4 mkv avi mov webm"
    echo "        image -> jpg jpeg png gif bmp webp"
    echo "  --skip-errors           Do not stop the program if an error occurs."
    echo
    echo "  -p, --pattern PATTERN   Rename pattern made out of tokens"
    echo
    echo "TOKENS:"
    echo "  {num} {num:04}"
    echo "  {name} {name:lower} {name:upper}"
    echo "  {ext} {dir} {size} {date}"
    echo "  {EXIF_TAG}"
    echo
    echo "EXAMPLE:"
    echo "  $0 -t image -p \"IMG_{num:04}\""
    echo "  $0 -t image -p \"{date}_{name}\" -f"
    echo
    echo "  --number-mode           Change how token {num} count (default by directory)"
    echo
    echo "============================================================"
    exit 0
}

#------------------------------------------------------------
# GLOBALS
#------------------------------------------------------------
script_path="$(realpath "$0")"

files_list=()
dirs_list=()

declare -A dir_counters
declare -A exif_cache

target_dir="$(pwd)"

is_recursive=false
is_verbose=false
is_very_verbose=false
is_force=false

file_extensions=()
file_tag=""
rename_pattern=""
number_mode="per-dir"

skip_errors=false
file_counter=1

#------------------------------------------------------------
# CLEANUP
#------------------------------------------------------------
cleanup_on_exit() {
    kill "$spinner_pid" 2>/dev/null
    exit 0
}

#------------------------------------------------------------
# SPINNER
#------------------------------------------------------------
spinner_loop() {
    local s='/-\|'; local i=0
    while :; do
        printf "\rProcessing... %c" "${s:i++:1}"
        ((i==${#s})) && i=0
        sleep 0.1
    done
}

#------------------------------------------------------------
# TAGS
#------------------------------------------------------------
set_extensions_by_tag() {
    case "$file_tag" in
        music) file_extensions=(mp3 flac wav aac ogg m4a) ;;
        video) file_extensions=(mp4 mkv avi mov webm) ;;
        image) file_extensions=(jpg jpeg png gif bmp webp) ;;
    esac
}

#------------------------------------------------------------
# SANITIZE
#------------------------------------------------------------
sanitize() {
    local input="$1"

    input="${input//\//_}"
    input="${input//$'\n'/_}"
    input="${input//$'\r'/_}"

    input=$(printf "%s" "$input" | tr -d '\000-\037')

    [[ -z "$input" ]] && input="file"

    echo "$input"
}

#------------------------------------------------------------
# EXIF LOAD (FAST)
#------------------------------------------------------------
load_exif() {
    exif_cache=()
    while IFS=': ' read -r key value; do
        exif_cache["$key"]="$value"
    done < <(exiftool -s "$1")
}

#------------------------------------------------------------
# SCAN
#------------------------------------------------------------
scan_directory() {
    local dir="$1"

    [[ "$is_verbose" == true || "$is_very_verbose" == true ]] && \
        echo "Scanning directory: $dir"

    for entry in "$dir"/*; do
        [ -e "$entry" ] || continue

        if [[ -d "$entry" ]]; then
            if [[ "$is_recursive" == true ]]; then
                dirs_list+=("$entry")
                scan_directory "$entry"
            else
                [[ "$is_very_verbose" == true ]] && \
                    echo "Skipping directory (non-recursive): $entry"
            fi

        elif [[ -f "$entry" && "$entry" != "$script_path" ]]; then
            ext="${entry##*.}"

            if [[ ${#file_extensions[@]} -eq 0 ]] || [[ " ${file_extensions[*]} " == *" $ext "* ]]; then
                files_list+=("$entry")

                [[ "$is_very_verbose" == true ]] && \
                    echo "Matched file: $entry"
            else
                [[ "$is_very_verbose" == true ]] && \
                    echo "Skipped (extension filter): $entry"
            fi
        fi
    done
}

#------------------------------------------------------------
# PATTERN
#------------------------------------------------------------
parse_pattern_tokens() {
    local pattern="$1"
    pattern_tokens=()

    while [[ "$pattern" == *"{"*"}"* ]]; do
        prefix="${pattern%%\{*}"
        rest="${pattern#*\{}"
        token="${rest%%\}*}"
        suffix="${rest#*\}}"

        [[ -n "$prefix" ]] && pattern_tokens+=("TEXT:$prefix")
        pattern_tokens+=("TOKEN:$token")
        pattern="$suffix"
    done

    [[ -n "$pattern" ]] && pattern_tokens+=("TEXT:$pattern")
}

#------------------------------------------------------------
# TOKEN RESOLVE
#------------------------------------------------------------
resolve_token() {
    local token="$1"
    local file="$2"

    key="${token%%:*}"
    format="${token#*:}"
    [[ "$key" == "$format" ]] && format=""

    case "$key" in
        num) printf "%0${format:-0}d" "$file_counter"; return ;;
        name) val="${file##*/}"; val="${val%.*}" ;;
        ext) val="${file##*.}" ;;
        dir) val="$(basename "$(dirname "$file")")" ;;
        size) val="$(stat -c%s "$file")" ;;
        date) val="$(stat -c "%y" "$file" | cut -d' ' -f1)" ;;
        *) val="${exif_cache[$key]}" ;;
    esac

    [[ -z "$val" ]] && return 1

    case "$format" in
        lower) val="${val,,}" ;;
        upper) val="${val^^}" ;;
    esac

    sanitize "$val"
}

#------------------------------------------------------------
# BUILD NAME
#------------------------------------------------------------
build_filename() {
    local file="$1"
    local out=""

    for part in "${pattern_tokens[@]}"; do
        type="${part%%:*}"
        val="${part#*:}"

        if [[ "$type" == "TEXT" ]]; then
            out+="$val"
        else
            resolved=$(resolve_token "$val" "$file") || return 1
            out+="$resolved"
        fi
    done

    echo "$out"
}

#------------------------------------------------------------
# RENAME / PREVIEW
#------------------------------------------------------------
rename_files() {
    declare -A name_counters

    for file in "${files_list[@]}"; do
        dir="$(dirname "$file")"

        [[ -z "${dir_counters[$dir]}" ]] && dir_counters[$dir]=1
        file_counter="${dir_counters[$dir]}"

        if [[ "$number_mode" == "per-dir" ]]; then
            [[ -z "${dir_counters[$dir]}" ]] && dir_counters[$dir]=1
            file_counter="${dir_counters[$dir]}"
        fi

        load_exif "$file"

        new_name=$(build_filename "$file") || {
            [[ "$skip_errors" == true ]] && continue
            echo "Error: $file"
            exit 1
        }

        base="${new_name%.*}"
        ext="${new_name##*.}"
        [[ "$base" == "$ext" ]] && ext=""

        key="$dir/$base.$ext"
        count="${name_counters[$key]:-0}"

        if [[ "$count" -gt 0 ]]; then
            final="${base}_$count.$ext"
        else
            final="${base}.$ext"
        fi

        ((name_counters[$key]++))

        new_path="$dir/$final"

        if [[ "$is_verbose" == true || "$is_very_verbose" == true ]]; then
            printf "OLD: %s\nNEW: %s\n\n" "$file" "$new_path"
        fi

        if [[ "$is_force" == true ]]; then
            mv -n -- "$file" "$new_path"
        fi

        if [[ "$number_mode" == "per-dir" ]]; then
            ((dir_counters[$dir]++))
        else
            ((file_counter++))
        fi
    done
}

#------------------------------------------------------------
# ARGUMENTS
#------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    echo "Use -h or --help for help"
    exit 0
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) print_help ;;
        -d|--directory) target_dir="$2"; shift ;;
        -r|--recursive) is_recursive=true ;;
        -v|--verbose) is_verbose=true ;;
        -vv|--very-verbose) is_very_verbose=true ;;
        -f|--force) is_force=true ;;
        -p|--pattern) rename_pattern="$2"; shift ;;
        -t|--tag) file_tag="$2"; set_extensions_by_tag; shift ;;
        -e|--extensions)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                file_extensions+=("$1"); shift
            done
            continue ;;
        --skip-errors) skip_errors=true ;;
        --number-mode) number_mode="$2";;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

#------------------------------------------------------------
# DEPENDENCIES
#------------------------------------------------------------
command -v exiftool >/dev/null || install_deps exiftool

#------------------------------------------------------------
# RUN
#------------------------------------------------------------
parse_pattern_tokens "$rename_pattern"

trap cleanup_on_exit SIGINT SIGTERM EXIT

if [[ "$is_verbose" == false && "$is_very_verbose" == false ]]; then
    spinner_loop &
    spinner_pid=$!
fi

scan_directory "$target_dir"

echo
echo "================ SCAN SUMMARY ================"
echo "Target directory : $target_dir"
echo "Recursive        : $is_recursive"
echo "Pattern          : $rename_pattern"
echo "Number mode      : $number_mode"

if [[ ${#file_extensions[@]} -gt 0 ]]; then
    echo "Extensions       : ${file_extensions[*]}"
else
    echo "Extensions       : (all)"
fi

[[ -n "$file_tag" ]] && echo "Tag filter       : $file_tag"

echo "---------------------------------------------"
echo "Files found      : ${#files_list[@]}"
echo "Directories found: ${#dirs_list[@]}"
echo "============================================="
echo

IFS=$'\n' files_list=($(printf "%s\n" "${files_list[@]}" | sort -V))

[[ -n "$spinner_pid" ]] && kill "$spinner_pid" 2>/dev/null

if [[ "$is_force" == false ]]; then
    echo "================================================="
    echo "PREVIEW ONLY (safe mode)"
    echo "No files were changed."
    echo "Use -f to enable actual renaming."
    echo "================================================="
    read -p "Type 'yes' to proceed showing renaming: " confirm
    [[ "$confirm" == "yes" ]] || exit 0
    is_verbose=true
    rename_files
    exit 0
fi

echo
echo "================================================="
echo "⚠️  WARNING: You are about to rename files!"
echo "This operation CANNOT be easily undone."
echo "================================================="

read -p "Type 'yes' to proceed: " confirm
[[ "$confirm" == "yes" ]] || exit 0

echo
echo "Applying changes..."

if [[ "$is_verbose" == false && "$is_very_verbose" == false ]]; then
    spinner_loop &
    spinner_pid=$!
fi

rename_files

[[ -n "$spinner_pid" ]] && kill "$spinner_pid" 2>/dev/null

echo
echo "Done."

