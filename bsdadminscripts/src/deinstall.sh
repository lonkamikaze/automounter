#!/bin/sh -f

. install.inc

for file in $files; {
	test -z "$file" && continue
	target="${file##*,}"
	echo "deleting: $target"
	rm "$target"
}

for link in $links; {
	test -z "$link" && continue
	target="${link##*,}"
	echo "unlinking: $target"
	rm "$target"
}

