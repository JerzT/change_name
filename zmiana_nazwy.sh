#!/bin/bash

#prepere program
listOfFiles=()
listOfDirectories=()
verboseON=0
directory="$(pwd)"
recursive=0

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

    for d in "${dirs[@]}"; do
        look_for_directories_and_files "$d"
    done
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [-h] [-v] [-r] [-d directory]"
            echo "  -h, --help        Show this help"
            echo "  -v, --verbose     Enable verbose mode"
            echo "  -d, --directory   Set directory"
            echo " -r, --recursive    Enable program going into directories"
            exit 0
            ;;
        -v|--verbose)
            verboseON=1
            ;;
        -d|--directory)
            directory="$2"
            shift
            ;;
        -r|--recursive)
            recursive=1
            ;;
        *)
            echo "Unknown option: $1"
            exit 0
            ;;
    esac
    shift
done

look_for_directories_and_files "$directory"

#filesInDirectory=${#listOfFiles[@]}
#echo ${filesInDirectory}
#echo ${listOfFiles[*]}
# echo $directory

for a in "${listOfFiles[@]}"
do
    echo "$(stat -c "%n %w" "$a")"
done

: <<'END'
file="zad1.c"
file_name="$(stat -c %n $file)"
birth="$(stat -c %w $file)"
echo "$file_name, $birth"
END

