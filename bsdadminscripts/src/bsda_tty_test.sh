#!/bin/sh
bsda_dir="${0%${0##*/}}"
. ${bsda_dir:-.}/bsda_tty.sh
bsda:tty:Terminal term
class=bsda:tty:Terminal
$term.use 6
$term.line 0 '------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
index=0
for file in *; do
	$term.stdout "$file"
	$term.format status '<03:d>: <x-:s>' $index "$file"
	$term.line $((index % 5  + 1)) "$status"
	index=$((index + 1))
done
ls -f | grep -n '' | $term.stdout
$term.delete
