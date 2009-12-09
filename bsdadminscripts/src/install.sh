#!/bin/sh -f

. install.inc

for file in $files; {
	test -z "$file" && continue
	source="${file%%,*}"
	mode="${file%,*}"
	mode="${mode#*,}"
	target="${file##*,}"
	echo "installing: $target"
	mkdir -p "${target%/*}"
	eval "$replace_cmd '$source'" > "${target%.gz}"
	test "${target%.gz}" != "$target" && gzip -f9 "${target%.gz}"
	chmod "$mode" "$target"
}

for link in $links; {
	test -z "$link" && continue
	source="${link%%,*}"
	mode="${link%,*}"
	mode="${mode#*,}"
	target="${link##*,}"
	echo "hardlinking: $source -> $target"
	mkdir -p "${target%/*}"
	ln -f "$source" "$target"
	chmod "$mode" "$target"
}

