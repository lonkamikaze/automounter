#!/bin/sh -f
#
# Copyright (c) 2009
# Dominic Fandrey <kamikaze@bsdforen.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# version 0.9

# Include once.
test -n "$bsda_tty" && return 0
bsda_tty=1

# Include framework for object oriented shell scripting.
. ${bsda_dir:-.}/bsda_obj.sh

#
# A package for controlling the terminal and mixing status output on
# /dev/tty with regular output on /dev/stdout and /dev/stderr in such
# a way that the using code does not have to know whether /dev/stdout
# is a terminal or a file.
#

#
# A list of useful termcap(5) capabilities, useful with tput(1):
# 	save_cursor		sc
#	restore_cursor		rc
#	cursor_address		cm #1 #2
#	cursor_home		ho
#	columns			co
#	lines			li
#	clr_eol			ce
#	clr_eos			cd
#	delete_line		dl
#	cursor_invisible	vi
#	cursor_normal		ve
#	cursor_visible		vs
#	parm_down_cursor	DO #1
#	parm_up_cursor		UP #1
#	carriage_return		cr
#

# Terminal exceptions.
readonly bsda_tty_ERR_TERMINAL_STATUSPROVIDER_INVALID=1
readonly bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS=2
readonly bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST=1

#
# An error storage variable.
# If an error occurs this should be set back to 0 wherever the error is
# dealt with.
#
bsda_tty_errno=0

#
# A helper function library.
#
bsda:obj:createClass bsda:tty:Library \
	x:public:format \
		"A printf wrapper to format a line adjusted to the available" \
		"terminal space." \
	x:public:convertBytes \
		"Provides byte count representations." \

#
# Convert byte counts into human readable values.
#
# This method runs out of units when peta bytes are reached.
#
# @param 1
#	The variable to return the converted byte in.
# @param 2
#	The variable to return the the conversion unit in.
# @param 3
#	The value to convert.
# @param 4
#	The optional targeted maximum string length. A length below 3 may lead
#	to 0 values, the default length is 4.
#
bsda:tty:Library.convertBytes() {
	local width unit value scale decscale rest
	width=${4:-4}
	value="$(($3))"

	# Binary scaling factor as powers of 2.
	scale=0
	# Decimal scaling mutiplier.
	decscale=1
	for unit in b k m g t p; do
		test ${#value} -le $width && break
		# Record scaling factors to calculate the rest.
		scale=$((scale + 10))
		decscale=$((decscale * 1000))
		# Convert the value to the next unit.
		value=$((value >> 10))
	done

	# Get the remainder out of the original value and scale it to a
	# decimal representation.
	rest=$((($3 - (value << scale)) * decscale / (1 << scale)))

	# Pad the value with digits.
	if [ $((${#value} + 1)) -lt $width ]; then
		value="$value."
		while [ ${#value} -lt $width ]; do
			value="$value${rest%%${rest#?}}"
			rest="${rest#?}"
		done
	fi

	# Return results.
	$caller.setvar "$1" "$value"
	$caller.setvar "$2" "$unit"
}

#
# A printf wrapper that allows x-length columns that will stretch to use an
# entire terminal line. Overlong columns are forcibly shortened.
#
# The padding/shrinking of x-length columns is weighted according to the
# length of the corresponding arguments. To retain a consistent layout over
# several calls, only a single x-length column should be used.
#
# Under no circumstances will a line with more characters than available
# terminal columns be output. Should the terminal be unable to report the
# available columns, 80 is assumed.
#
# The following things break this function:
#	\r, \n, \t
#		The formatting characters are all counted as 1 regular
#		character, so the output may end up too short or spreading
#		more than 1 line
#	unmatching number of arguments
#		Providing the wrong number of arguments, causes them to show
#		up in the wrong output columns
#
# Format pattern insertions are defined in the following way:
#	PADDING :=	"0" | "-" | ""
#	WIDTH :=	[[:digit:]]* | "x" | ""
#	CUT :=		"-" | ""
#	STYLE :=	[[:alpha:]]
#	FORMAT :=	"<" PADDING WIDTH CUT ":" STYLE ">"
#
# PADDING	"0"		The value is left-filled with "0"
#		"-"		The value is right-padded
#		""		The value is left-padded
#
# WIDTH		[[:digit:]]*	A numeric value
#		"x"		Auto-adjust
#		""		No adjustment
#
# CUT		"-"		Remove characters from the beginning
#		""		Remove trailing characters
#
# STYLE		[[:alpha:]]	A character from the alphabet declaring a
#				printf style
#
# @param 1
#	The return variable name.
# @param 2
#	The pattern to convert and use.
# @param @
#	The remaining arguments will be passed on to printf.
#
bsda:tty:Library.format() {
	local IFS outvar pattern printf columns format arg width pad style
	local cutdirection output adjust xlen rest

	IFS='
'

	outvar="$1"
	pattern="$2"
	shift 2
	columns=$(tput co || echo 80)

	#
	# Normally the format pattern is parsed two times. The first time
	# hard coded column widths are enforced on the arguments. Afterwards
	# A render attempt is made, which provides the difference to the
	# desired output width.
	#

	# Working copy of the provided pattern.
	printf="$pattern"
	# Sum up the length of dynamically spaced arguments.
	xlen=0
	for format in $(echo "$pattern" | egrep -o '<[0-]?([[:digit:]]*|x)-?:[[:alpha:]]>'); do
		# Get the formatting values
		style="${format##*:}";style="${style%>}"
		width="${format#<}";width="${width#[0-]}";width="${width%%:*}";width="${width%-}"
		pad="${format#<}";pad="${pad%%${pad#[0-]}}"
		cutdirection="${format%%:*}";cutdirection="${cutdirection#${cutdirection%-}}"

		# Get the argument, empty arguments are replaced with 0 or
		# space, depending on the padding setting.
		arg="${1:-${pad:- }${pad#-}}"
		arg="${arg:- }"
		shift

		if [ "$width" = "x" ]; then
			# Unset column with for the first rendering
			width=
			# Record argument length
			xlen=$((xlen + ${#arg}))
		elif [ -n "$width" -a "$width" -lt "${#arg}" ]; then
			# Limit to the width if one was specified.
			if [ -n "$cutdirection" ]; then
				# Cut from the left.
				arg="$(echo "$arg" | sed -E "s,.*(.{$width})$,\1,")"
			else
				# Cut from the right.
				arg="$(echo "$arg" | sed -E "s,^(.{$width}).*,\1,")"
			fi
		fi 2> /dev/null

		# Preserve argument.
		set -- "$@" "$arg"
		printf="$(echo "$printf" | sed -E "s,$format,%$pad$width$style,")"
	done
	output="$(printf "$printf" "$@")"

	#
	# The second pattern parsing is performed to adjust the width of
	# auto-adjusted colums. This can either mean cutting excess characters
	# away or to perform aditional padding.
	#
	# If no auto-adjusted columns exist or the first render attempt
	# yielded the correct width, the second pass is skipped and the first
	# pass prevails as the output.
	#

	#
	# Apply the appropriate padding/shrinking strategy.
	#

	# How many columns have to be added/removed?
	adjust=$((columns - ${#output}))
	if [ $xlen -eq 0 ]; then
		: # Nothing to stretch/shrink.
	elif [ $adjust -ne 0 ];  then
		# Pad/shrink arguments.
		printf="$pattern"
		for format in $(echo "$pattern" | egrep -o '<[0-]?([[:digit:]]*|x)-?:[[:alpha:]]>'); do
			arg="$1"
			shift
			# Get the values
			style="${format##*:}";style="${style%>}"
			width="${format#<}";width="${width#[0-]}";width="${width%%:*}";width="${width%-}"
			pad="${format#<}";pad="${pad%%${pad#[0-]}}"
			cutdirection="${format%%:*}";cutdirection="${cutdirection#${cutdirection%-}}"
	
			if [ "$width" = "x" ]; then
				# Calculate new arg length.
				width=$((${#arg} + adjust * ${#arg} / xlen))
				rest=$((adjust * ${#arg} % xlen))
				if [ $rest -lt 0 ]; then
					width=$((width - 1))
					adjust=$((adjust + 1))
				elif [ $rest -gt 0 ]; then
					width=$((width + 1))
					adjust=$((adjust - 1))
				fi
				if [ $adjust -lt 0 ]; then
					# Remove from arg.
					if [ -n "$cutdirection" ]; then
						# Cut from the left.
						arg="$(echo "$arg" | sed -E "s,.*(.{$width})$,\1,")"
					else
						# Cut from the right.
						arg="$(echo "$arg" | sed -E "s,^(.{$width}).*,\1,")"
					fi 2> /dev/null
				fi
			fi
	
			# Preserve argument.
			set -- "$@" "$arg"
			printf="$(echo "$printf" | sed -E "s,$format,%$pad$width$style,")"
		done
	fi

	# Return the result.
	output="$(printf "$printf" "$@" | sed -E "s,^(.{$columns}),\1,")"
	$caller.setvar "$outvar" "$output"
}

bsda:obj:createInterface bsda:tty:StatusProvider \
	x:requestStatus \
		"Expected to return a status line to the first parameter." \
	x:disconnectStatus \
		"Is called if the status provider gets disconnected." \

#
# Represents a terminal to controll output on stdout, stderr and status lines.
#
# An instance can be deactivated, in which case status messages are discarded.
#
# For convenience it also inherits the methods of the helper function library.
#
bsda:obj:createClass bsda:tty:Terminal extends:bsda:tty:Library\
	w:private:active \
		"Terminal control active flag." \
	w:private:count \
		"The number of lines dedicated to status output." \
	w:private:visible \
		"The current visibility state." \
	w:private:providers \
		"A list of references to StatusProvider instances." \
	w:private:buffer \
		"A buffer of the status lines, for show." \
	i:private:init \
		"The constructor checks whether a terminal is available." \
	c:private:clean \
		"Notifies the StatusProvider instances." \
	x:private:draw \
		"Draws the buffer." \
	x:public:deactivate \
		"Deactivates the Terminal controlling methods." \
	x:public:use \
		"Controls the number of lines used for status display." \
	x:public:hide \
		"Hide the status lines." \
	x:public:show \
		"Recover the last status display." \
	x:public:refresh \
		"Refresh status lines." \
	x:public:attach \
		"Attach a StatusProvider to a status line." \
	x:public:line \
		"Sets a status line." \
	x:public:stdout \
		"Write to stdout." \
	x:public:stderr \
		"Write to stderr." \

#
# The constructor checks whether a terminal is available.
#
bsda:tty:Terminal.init() {
	if [ -e /dev/tty ]; then
		tput vi
		$this.setActive 1
		$this.setCount 0
		$this.setVisible 1
	fi
}

bsda:tty:Terminal.clean() {
	local IFS providers provider active

	IFS='
'
	$this.getActive active
	if [ -n "$active" ]; then
		$this.hide
		tput ve > /dev/tty
	fi

	$this.getProviders providers
	for provider in $providers; do
		if bsda:tty:StatusProvider.isInstance "$provider"; then
			$provider.disconnectStatus
		fi
	done


	return 0
}

#
# Draw the buffer to stdout, make sure not to use more lines than the terminal
# currently provides.
#
# Falls back to 24 lines if the terminal does not report them.
#
bsda:tty:Terminal.draw() {
	local buffer lines count

	$this.getCount count
	lines=$(tput li || echo 24)
	if [ $count -lt $lines ]; then
		count="$lines"
	fi

	buffer="$($this.getBuffer | tail -n $count)."
	tput cr cd
	echo -n "${buffer%.}"
	tput cr UP $((count - 1))

}

#
# Deactivates terminal handling.
#
bsda:tty:Terminal.deactivate() {
	$this.reset
	$this.setActive
}

#
# @param 1
#	The number of status lines to use.
#
bsda:tty:Terminal.use() {
	local IFS active count buffer providers provider index

	$this.getActive active
	test -n "$active" && return

	IFS='
'

	#
	# Two cases, the new number of lines is greater or smaller.
	#
	$this.getCount count
	$this.getProviders providers
	$this.getBuffer buffer
	if [ $count -gt $1 ]; then
		# Lower the count.
		index=0
		for provider in $providers; do
			if [ $index -ge $1 ]; then
				if bsda:tty:StatusProvider.isInstance "$provider"; then
					$provider.disconnectStatus
				fi
			fi
			index=$((index + 1))
		done
		if [ $1 -gt 0 ]; then
			providers="$(echo "$providers." | head -n $1)"
			providers="${providers%.}"
			buffer="$(echo "$buffer." | tail -n $1)"
			buffer="${buffer%.}"
		else
			providers=
		fi
	elif [ $count -lt $1 ]; then
		# Increase the count.
		for index in $(jot $(($1 - count))); do
			providers="$providers$IFS"
			buffer="$IFS$buffer"
		done
	fi

	$this.hide
	$this.setProviders "$providers"
	$this.setBuffer "$buffer"
	$this.setCount $1
	$this.show
}

bsda:tty:Terminal.hide() {
	local active visible

	$this.getActive active
	test -n "$active" && return

	IFS='
'

	$this.getVisible visible

	if [ -n "$visible" ]; then
		tput cd
		$this.setVisible
	fi > /dev/tty
}

bsda:tty:Terminal.show() {
	local active visible

	$this.getActive active
	test -n "$active" && return

	$this.getVisible visible

	if [ -z "$visible" ]; then
		$this.draw
		$this.setVisible 1
	fi > /dev/tty
}

#
# 
# @param @
#	Each parameter represents a line index or a StatusProvider instance.
# @throws bsda_tty_ERR_TERMINAL_STATUSPROVIDER_NOT_IN_LIST
#	Is thrown if an invalid provider was given.
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
#	Is thrown if an inexistant index line is given.
#
bsda:tty:Terminal.refresh() {
	local active

	$this.getActive active
	test -n "$active" && return

	#TODO
}

#
# Attach a StatusProvider.
#
# Either attaches the provider to a specific line or if no line is provided
# creates a new one.
#
# Lines are counted from bottom to top, starting at 0.
#
# @param 1
#	The StatusProvider instance to attach.
# @param 2
#	The index of the line to attach the provider to, optional.
# @throws bsda_tty_ERR_TERMINAL_STATUSPROVIDER_INVALID
#	Is thrown if an invalid provider was given.
# @throws bsda_tty_ERR_TERMINAL_LINEINDEX_OUT_OF_BOUNDS
#	Is thrown if the given line index is outside of the scope of currently
#	managed lines.
#
bsda:tty:Terminal.attach() {
	local active index count buffer providers provider line

	$this.getActive active
	test -n "$active" && return

	# Check whether a valid StatusProvider has been given.
	provider="$1"
	if ! bsda:tty:StatusProvider.isInstance "$provider"; then
		bsda_tty_errno=$bsda_tty_ERR_TERMINAL_PROVIDER
		return 1
	fi

	index="$2"
	$this.getCount count

	# Set a proper index.
	if bsda:obj:isUInt "$index"; then
		if [ $index -ge $count -o $index -lt 0 ]; then
			bsda_tty_errno=$bsda_tty_ERR_TERMINAL_LINEINDEX
			return 1
		fi
		$this.detach $index
	else
		index=$count
		$this.use $((count + 1))
	fi

	# Update the buffer.
	$provider.requestStatus line
	buffer="$($this.getBuffer | sed "$((count - $index))c\\$IFS$line$IFS")."
	$this.setBuffer "${buffer%.}"
	# Draw the updated buffer.
	$this.draw
	
	# Attach the provider.
	providers="$($this.getProviders | sed "$((index + 1))c\\$IFS$provider$IFS")."
	$this.setProviders "${providers%.}"
}

bsda:tty:Terminal.detach() {
	local active

	$this.getActive active
	test -n "$active" && return

	#TODO
}

bsda:tty:Terminal.line() {
	local active

	$this.getActive active
	test -n "$active" && return

	#TODO
}

bsda:tty:Terminal.stdout() {
	local active

	$this.getActive active

	#TODO
}

bsda:tty:Terminal.stderr() {
	local active

	$this.getActive active

	#TODO
}

