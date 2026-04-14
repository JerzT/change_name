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

            for e in "${extensions[@]}"; do
                if [[ "$ext" == "$e" ]]; then
                    current_files+=("$a")
                    listOfFiles+=("$a")
                    break
                fi
            done
        fi
    done

    if  [ $verbouse = true -o $verbVerbouse = true ]; then
        printf "\nChecked directory: %s\n" "$current_dir\n"
        printf "Files found: ${#current_files[@]}\n"
        printf "Directories found: ${#dirs[@]}\n"
    fi

    if [ $verbVerbouse = true ]; then
        for b in "${current_files[@]}"; do
            printf "File $b found in directory: $current_dir\n"
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

#---------------------------------------------------------------------------------------------#
# argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [-h] [-r] [-d directory]"
            echo "  -h, --help            Show this help"
            echo "  -d, --directory       Set directory"
            echo "  -r, --recursive       Enable recursive search"
            echo "  -v, --verbouse        Print more info throught process"
            echo "  -vv --verb-verbouse   Print all processes"
            echo "  -f, --force           Force every changes for files"
            echo "  -e, --extensions      Specify extensions of looked files"
            echo "  -p, --pattern         Specify pattern of chnaged name"
            echo "  -t, --tag             Use one of the tags to choose some type of a file"
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
            verbouse=true
            ;;
        -vv|--verb-verbouse)
            verbVerbouse=true
            ;;
        -e|--extensions)
            shift
            while [[ $# -gt 0 && "$1" != -* ]]; do
                extensions+="$1"
            done
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
# prepare program
SCRIPT_PATH="$(realpath "$0")"
listOfFiles=()
listOfDirectories=()
directory="$(pwd)"
recursive=false
verbouse=false
verbVerbouse=false
force=false
extensions=()

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
