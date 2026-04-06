file="zad1.c"
file_name="$(stat -c %n $file)"
birth="$(stat -c %w $file)"
echo "$file_name, $birth"


