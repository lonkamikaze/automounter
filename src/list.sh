#!/bin/sh -fCe

. install.inc

for file in $files; {
	test -z "$file" && continue
	target="${file##*,}"
	target="${target#$rmPrefix}"
	echo "$target"
}

