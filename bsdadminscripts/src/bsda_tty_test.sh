. bsda_tty.sh
bsda:tty:Terminal term
class=bsda:tty:Terminal
$term.use 6
$term.line 0 '------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
index=0
for file in *; do
#	if [ $index -eq 0 ]; then
#		$term.hide
#		$term.getBuffer
#		$term.show
#	fi
	#sleep 0.2
	#echo "$file" | $term.stdout
	$term.stderr "$file"
	$term.line $((index % 5  + 1)) "$(printf "%03d - %s" $((index + 1)) "$file" )"
	index=$((index + 1))
	#sleep 0.2
done
ls -f | grep -n '' | $term.stderr
#sleep 3
$term.delete
