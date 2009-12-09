#!/bin/sh -f

. install.inc

for file in $files; {
	test -z "$file" && continue
	target="${file##*,}"
	target="${target#$rmPrefix}"
	echo "$target"
}

for link in $links; {
	test -z "$link" && continue
	target="${link##*,}"
	target="${target#$rmPrefix}"
	echo "$target"
}

