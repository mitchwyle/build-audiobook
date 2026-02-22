# Create the file and handle potential single quotes in filenames
printf "file '%s'\n" *.mp3 | sort -V | sed "s/'/'\\\\''/g; s/file '\\\\''/file '/; s/\\\\''$/'/" > ./concat-list.txt
ffmpeg -f concat -safe 0 -i ./concat-list.txt -map 0:a -c:a aac -b:a 128k -f ipod out.m4b
