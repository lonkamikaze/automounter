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
# version 1.0

# Include once.
test -n "$bsda_out" && return 0
bsda_out=1

#
# This file offers output functions.
#
# @param name
#	The name of the script using the functions.
#

# Parameter flags.
bsda_out_pClean=
bsda_out_pVerbose=
bsda_out_pNoLogging=

# The default log file.
bsda_out_logfile="%%VAR%%/log/$name.log"

# The current status line.
bsda_out_status=

#
# Table Of Functions
# In order of appearance.
#
# bsda:out:status()		Print status messages on the terminal
# bsda:out:error()		Terminate with an error message
# bsda:out:warn()		Print a warning on stderr
# bsda:out:verbose()		Print a message, but only in verbose mode
# bsda:out:log()		Log activity into a log file
# bsda:out:progress()		Print numerical progress output
# bsda:out:echo()		Display a message preserving the status line
# 

#
# Prints a status message to the terminal device /dev/tty.
#
# @param 1
#	The message to print
# @param bsda_out_status
#	The last printed message, used for clearing the status line before
#	printing a new status.
# @param bsda_out_pClean
#	If set, do not print status messages.
#
bsda:out:status() {
	test -n "$bsda_out_pClean" && return 0
	printf "\r%${#bsda_out_status}s\r%s\r" '' "$1" > /dev/tty
	bsda_out_status="$1"
}

#
# Exits with the given error and message on stderr.
#
# @param 1
#	The error number to exit with.
# @param 2
#	The message to exit with.
#
bsda:out:error() {
	# Clear the status line.
	bsda:out:status
	echo "$name: $2" 1>&2
	exit "$1"
}

#
# Writes a warning message to stderr.
#
# @param 1
#	The message to write.
#
bsda:out:warn() {
	# Clear the status line.
	bsda:out:status
	echo "$name: $1" 1>&2
}

#
# Outputs verbose messages on stdout.
#
# @param @
#	All the parameters to be output.
# @param bsda_out_pVerbose
#	If this is not set, do not output anything.
#
bsda:out:verbose() {
	test -z "$bsda_out_pVerbose" && return 0
	echo "$@"
}

#
# Logs the given message into a log file.
#
# The following format is used.
#
# <UTC timestamp> - <date> - (<error>|MESSAGE): <message>
#
# UTC timestamp := The output of 'date -u '+%s'
# date := The output of 'date'
#
# @param 1
#	The error number for the log, if this is 0, the message will be
#	preceded by "DONE:" instead of "ERROR($1):".
# @param 2
#	The message to log.
# @param bsda_out_logfile
#	The name of the file to log into.
# @param bsda_out_pNoLogging
#	If set, logging is not performed.
#
bsda:out:log() {
	test -n "$bsda_out_pNoLogging" && return 0

	if [ $1 -eq 0 ]; then
		echo "$(date -u '+%s') - $(date) - MESSAGE: $2" >> $bsda_out_logfile
	else
		echo "$(date -u '+%s') - $(date) - ERROR($1): $2" >> $bsda_out_logfile
	fi
}

#
# Prints a progress message to the terminal device /dev/tty.
#
# @param 1
#	Total amount of operations to do.
# @param 2
#	The amount of operations performed.
# @param 3
#	The name of the package that is currently operated on.
# @param 4
#	The text prepending the progress information.
# @param bsda_out_status
#	The last printed message, used for clearing the status line before
#	printing a new status.
# @param bsda_out_pClean
#	If set, do not print progress messages.
#
bsda:out:progress() {
	test -n "$bsda_out_pClean" && return 0
	printf "\r%${#bsda_out_status}s\r$4 %${#1}s of %${#1}s (%3s%%) <$3>.\r" '' "$2" "$1" "$(($2 * 100 / $1))" > /dev/tty
	bsda_out_status="$4 $1 of $1 (100%) <$3>."
}

#
# Displays a message preserving the status line.
#
# @param @
#	The message forwarded to the regular echo command.
#
bsda:out:echo() {
	local status
	status="$bsda_out_status"
	bsda:out:status
	echo "$@"
	bsda:out:status "$status"
}


#
# Static checks.
#

# Implicit clean output without a terminal.
test ! -e "/dev/tty" && bsda_out_pClean=1

