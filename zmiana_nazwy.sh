#!/bin/bash
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

cleanup() {
    printf "Stopping...\n"
    kill "$spinner_pid" 2>/dev/null
    exit 1
}

look_for_directories_and_files () {
    local current_dir="$1"
    local current_files=()
    local dirs=()

    for a in "$current_dir"/*; do
        [ -e "$a" ] || continue

        if [ -d "$a" ]; then
            if [ $recursive = true ]; then
                dirs+=("$a")
                listOfDirectories+=("$a")
            fi

        else
            if [ $SCRIPT_PATH = "$a" ]; then
                continue
            fi

            ext="${a##*.}"

            if [[ ${#extensions[@]} = 0 ]];then
                current_files+=("$a")
                listOfFiles+=("$a")
                continue
            fi

            for e in ${extensions[@]}; do
                if [[ "$ext" == "$e" ]]; then
                    current_files+=("$a")
                    listOfFiles+=("$a")
                    break
                fi
            done

        fi
    done

    if  [ $verbose = true -o $very_verbose = true ]; then
        printf "\nChecked directory: %s\n" "$current_dir\n"
        printf "Files found: ${#current_files[@]}\n"
        printf "Directories found: ${#dirs[@]}\n"
    fi

    if [ $very_verbose = true ]; then
        for b in "${current_files[@]}"; do
            #printf "File $b found in directory: $current_dir\n"
            printf "File $b found\n"
        done
    fi

    for d in "${dirs[@]}"; do
        look_for_directories_and_files "$d"
    done
}

change_name_of_files () {
    for a in "${listOfFiles[@]}";do
        echo $(exiftool -common $a)
    done
}

spin() {
    local sp='/-\|'
    local sc=0
    while :; do
        printf "\rProcessing... %c" "${sp:sc++:1}"
        ((sc==${#sp})) && sc=0
        sleep 0.1
    done
}

set_extension_by_tag() {
    case "$tag" in
        music)
            extensions=("mp3" "flac" "wav" "aac" "ogg")
            ;;
        video)
            extensions=("mp4" "mkv" "avi" "mov" "webm")
            ;;
        images)
            extensions=("jpg" "jpeg" "png" "gif" "bmp" "webp")
            ;;
    esac
}

#---------------------------------------------------------------------------------------------#
# prepare program
SCRIPT_PATH="$(realpath "$0")"
listOfFiles=()
listOfDirectories=()
directory="$(pwd)"
recursive=false
verbose=false
very_verbose=false
force=false
extensions=()
tag=""
ALLOWED_TAGS=("music" "video" "images")

#---------------------------------------------------------------------------------------------#
# argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [options]"
            echo
            echo "Options:"
            echo "  -h, --help              Show this help message"
            echo "  -d, --directory DIR     Set target directory"
            echo "  -r, --recursive         Enable recursive search"
            echo "  -v, --verbose           Print more info during process"
            echo "  -vv, --very-verbose     Print detailed process info"
            echo "  -f, --force             Force changes for files"
            echo "  -e, --extensions        List of file extensions (space-separated)"
            echo "  -p, --pattern PATTERN   Specify rename pattern"
            echo "  -t, --tag TAG           Use predefined tag: music, video, images (by using this option you disable extensions given by you)"
            exit 0
            ;;
        -d|--directory)
            directory="$2"
            shift
            ;;
        -r|--recursive)
            recursive=true
            ;;
        -v|--verbouse)
            verbose=true
            ;;
        -vv|--verb-verbouse)
            very_verbose=true
            ;;
        -e|--extensions)
            shift
            while [[ $# -gt 0 && "$1" != "-"* ]]; do
                extensions+=("$1")
                shift
            done
            continue
            ;;
        -p|--pattern)
            shift
            continue
            ;;
        -t|--tag)
            if [[ " ${ALLOWED_TAGS[@]} " =~ " $2 " ]]; then
                tag="$2"
                set_extension_by_tag
            else
                echo "Error: Invalid tag '$2'. Allowed values are: ${ALLOWED_TAGS[*]}"
                exit 1
            fi
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done


#---------------------------------------------------------------------------------------------#
#check dependencies
dependencies=(exiftool)
missing=()

for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing+=("$dep")
    fi
done
if [ ${#missing[@]} -ne 0 ]; then
    echo "Installing missing dependencies..."
    install_deps "${missing[@]}"
fi


#---------------------------------------------------------------------------------------------#
# run scan in background
trap cleanup SIGINT

# start spinner
if [ "$verbouse" = false ]; then
    spin &
    spinner_pid=$!
fi

#look for files and Directories
look_for_directories_and_files "$directory"

# stop spinner
kill "$spinner_pid" 2>/dev/null

# clear line and finish
printf "\n\rDone!                      \n"
printf "Files found: ${#listOfFiles[@]}\n"
printf "Directories found: ${#listOfDirectories[@]}\n"

#input from user
if [ $force = false ]; then
    read -p "Proceed to changing names? (y/n): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || cleanup
fi

change_name_of_files

printf "Program finished!"

exit 1
