#!/bin/bash

# prepare program
listOfFiles=()
listOfDirectories=()
directory="$(pwd)"
recursive=0
verbouse=0

cleanup() {
    printf "\nStopping...\n"
    kill "$spinner_pid" 2>/dev/null
    exit 1
}


look_for_directories_and_files () {
    local current_dir="$1"
    local dirs=()

    for a in "$current_dir"/*; do
        [ -e "$a" ] || continue

        if [ -d "$a" ]; then
            if [ "$recursive" -eq 1 ]; then
                dirs+=("$a")
                listOfDirectories+=("$a")
            fi
        else
            listOfFiles+=("$a")
        fi
    done

    if  [ "$verbouse" -eq 1 ]; then
        printf "Checked directory: %s\n" "$current_dir"
    fi

    for d in "${dirs[@]}"; do
        look_for_directories_and_files "$d"
    done
}

# spinner
spin() {
    local sp='/-\|'
    local sc=0
    while :; do
        printf "\rProcessing... %c" "${sp:sc++:1}"
        ((sc==${#sp})) && sc=0
        sleep 0.1
    done
}

# argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [-h] [-r] [-d directory]"
            echo "  -h, --help        Show this help"
            echo "  -d, --directory   Set directory"
            echo "  -r, --recursive   Enable recursive search"
            echo "  -v, --verbouse    Print more info throught process"
            exit 0
            ;;
        -d|--directory)
            directory="$2"
            shift
            ;;
        -r|--recursive)
            recursive=1
            ;;
        -v|--verbouse)
            verbouse=1
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# run scan in background
trap cleanup SIGINT

# start spinner
if [ "$verbouse" -eq 0 ]; then
    spin &
    spinner_pid=$!
fi

look_for_directories_and_files "$directory"



# stop spinner
kill "$spinner_pid" 2>/dev/null

# clear line and finish
printf "\rDone!                      \n"
printf "Files found: ${#listOfFiles[@]}\n"
printf "Directories found: ${#listOfDirectories[@]}\n"
