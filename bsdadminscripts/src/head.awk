#!/usr/bin/awk -f
#
# Copyright (c) 2010
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
# version 0.99

#
# Outputs a given number of lines, unlike head(1) lines are counted as they
# appear on the terminal.
#
# The properties of the terminal have to be supplied as parameters.
#
# @param 1
#	The number of terminal columns "tput co".
# @param 2
#	The number of terminal lines to output.
# @param 3
#	The tab stop width "tput it".
# @param 4
#	Has the newline glitch "tput xn".
#

BEGIN {
	# Use the first 4 arguments as terminal parameters.
	MAXCO = ARGV[1];
	MAXLI = ARGV[2];
	TABSTOPS = ARGV[3];
	GLITCH = ARGV[4];

	# Cannot return values above 255.
	if (MAXLI > 255)
		MAXLI = 255;

	# Throw them away, so they won't be openend as files.
	for (i = 1; i <= 4; i++)
		ARGV[i] = null;

	# Open stdin if no files were given.
	if (ARGC <= 5)
		ARGV[1] = "/dev/stdin";

	# Current line.
	line = 0;
	# Current xpos.
	xpos = 0;
	# Used to eat tabs after line overflow, on terminals without the
	# newline.
	eattabs = 0;

	# Don't eat new lines.
	RS = null;
}

function process(char) {
	# Detect overflowing lines on terminals with the newline glitch.
	if (GLITCH && xpos == MAXCO) {
		line++;
		xpos = 0;
	}

	# Detect overflowing lines on newline glitch eating terminals.
	if (!GLITCH && xpos == MAXCO && char != "\n" && char != "\r") {
		# Eat tabs after a line overflow.
		eattabs = 1;
		# Transition into the next line.
		line++;
		xpos = 0;
	}

	# Stop when the wanted line is met.
	# But put out eaten tabs first.
	if (line >= MAXLI && !(eattabs && char == "\t"))
		exit(line);

	# Calculate the xpos, line, behind this char.
	if (char == "\n") {
		# Transition into the next line.
		line++;
		xpos = 0;
	} else if (char == "\r") {
		xpos = 0;
	} else if (char == "\t") {
		if (!eattabs) {
			# Calculate tab stops correctly.
			xpos = xpos - xpos % TABSTOPS + TABSTOPS + 1;
			# Tabs never lead further than the last character of a line.
			if (xpos >= MAXCO)
				xpos = MAXCO - 1;
		}
	} else
		xpos++;

	# Turn off tab eating.
	if (char != "\t")
		eattabs = 0;

	# Finally, print the character.
	printf(char);
}

{
	split($0, chars, "");
	for (i = 1; i <= length(chars); i++)
		process(chars[i]);
}

END {
	process("\n");
	exit(line);
}
