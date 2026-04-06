#!/bin/bash

#prepere program
listOfFiles=()
verboseON=0
directory="$(pwd)"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [-h] [-v] [-d directory]"
            echo "  -h, --help        Show this help"
            echo "  -v, --verbose     Enable verbose mode"
            echo "  -d, --directory   Set directory"
            exit 0
            ;;
        -v|--verbose)
            verboseON=1
            ;;
        -d|--directory)
            directory="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 0
            ;;
    esac
    shift
done

for a in $(ls $directory)
do
  listOfFiles+=("$a")
done

filesInDirectory=${#listOfFiles[@]}
#echo ${listOfFiles[*]}
echo $directory

for a in "${listOfFiles[@]}"
do
    echo "$(stat -c %w "$directory/$a")"
done

: <<'END'
file="zad1.c"
file_name="$(stat -c %n $file)"
birth="$(stat -c %w $file)"
echo "$file_name, $birth"
END

