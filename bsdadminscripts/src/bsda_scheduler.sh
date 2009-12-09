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
test -n "$bsda_scheduler" && return 0
bsda_scheduler=1

# Include framework for object oriented shell scripting.
. bsda_obj.sh

#
# Offers classes and interfaces for a primitive scheduler.
#

#
# The following is a list of all classes and interfaces:
#	bsda:scheduler:Process		Process interface
#	bsda:scheduler:Scheduler	Scheduler interface
#	bsda:scheduler:Sleep		Sleep process
#	bsda:scheduler:RoundTripScheduler
#					A simple scheduler class
#




#
# This interface has to be implemented by every class that wants to register
# itself as a process for the scheduler.
#
bsda:obj:createInterface bsda:scheduler:Process \
	x:run \
		"This method is repeatedly called by the scheduler." \
	x:stop \
		"This method can be called by a scheduler when it is" \
		"stopped." \

#
# This interface has to be implemented by every scheduler.
#
bsda:obj:createInterface bsda:scheduler:Scheduler \
	x:register \
		"This method is called to register a processes." \
	x:unregister \
		"This method is called to unregister a process." \
	x:run \
		"This method is called to hand control over to the" \
		"scheduler." \
	x:stop \
		"This method should stop the scheduler."

#
# This class implements a sleeping process that can be used to lay a scheduler
# to rest for each run over the scheduler. This is useful to save CPU time.
#
# A sleeping process is dispatched with every run and with the next run the
# a Sleep object waits for the sleeping process to finish.
#
# The effect is that the given time is the maximum sleeping time between two
# run calls. If the time passed between two calls is greater than the sleeping
# interval, the process will not sleep at all.
#
bsda:obj:createClass bsda:scheduler:Sleep \
	implements:bsda:scheduler:Process \
	w:private:sleepPID \
		"The process ID for the sleep process." \
	w:private:time \
		"The time to sleep." \
	i:private:init \
		"The constructor sets the sleepig time."

#
# The constructor stores the sleeping time.
#
# @param 1
#	The time to sleep for every run provided in the simple float format.
# @return
#	0 if everything goes fine
#	1 if the given time is not a simple float
#
bsda:scheduler:Sleep.init() {
	bsda:obj:isSimpleFloat "$1" || return
	$this.setTime "$1"
}

#
# Sleep for the remaining amount of time.
#
bsda:scheduler:Sleep.run() {
	local time sleepPID
	$this.getTime time
	$this.getSleepPID sleepPID

	if [ -n "$sleepPID" ]; then
		wait $sleepPID
	fi

	sleep "$time" &
	$this.setSleepPID $!
}

#
# Does nothing.
#
bsda:scheduler:Sleep.stop() {
	# Reset the sleeping PID.
	$this.setSleepPID
}

#
# This class implements a simple round trip scheduler.
#
bsda:obj:createClass bsda:scheduler:RoundTripScheduler \
	implements:bsda:scheduler:Scheduler \
	-:running \
		"The state of the scheduler." \
	r:processes \
		"The list of processes." \
	r:protectedProcesses \
		"A list of self registered processes."

#
# Registers a process. If no process is given, the caller is registered.
# Processes registered in this way can only be unregister themselves.
#
# @param 1
#	An instance of bsda:scheduler:Process, if not given the calling
#	object is registered.
# @return
#	0 if everything goes fine
#	1 if the given object is not a process
#
bsda:scheduler:RoundTripScheduler.register() {
	local IFS

	IFS='
'

	# Check whether a parameter was given.
	if [ -n "$1" ]; then
		# Only accept processes.
		bsda:scheduler:Process.isInstance "$1" || return

		# Add process to the schedule.
		eval "${this}processes=\"\${${this}processes:+\${${this}processes}$IFS}$1\""
	else
		local process
		# Get the caller.
		$caller.getObject process

		# Only accept processes.
		bsda:scheduler:Process.isInstance "$process" || return

		# Add the process to the schedule.
		eval "${this}protectedProcesses=\"\${${this}protectedProcesses:+\${${this}protectedProcesses}$IFS}$process\""
	fi
}

#
# Removes a process from the schedule. Will unregister the caller
# if no process is given.
#
# @param 1
#	The optional process to unregister.
# @return
#	0 if everything goes fine
#	1 if the given process is not a bsda:scheduler:Process instance
#	2 if the given process is not registered 
#	3 if the process may not be unregistered by the caller
#
bsda:scheduler:RoundTripScheduler.unregister() {
	local process

	# Select the process to unregister.
	if [ -n "$1" ]; then
		process="$1"
	else
		$caller.getObject process
	fi

	# Check whether the process is a bsda:scheduler:Process instances.
	bsda:scheduler:Process.isInstance "$process" || return 1

	# Check whether the process is registered.
	if $this.getProcesses | grep -qFx "$process"; then
		setvar ${this}processes "$($this.getProcesses | grep -vFx "$process")"
	elif $this.getProtectedProcesses | grep -qFx "$process"; then
		# Check whether the caller may unregister the process.
		test "$($caller.getObject)" = "$process" || return 3
		setvar ${this}protectedProcesses "$($this.getProtectedProcesses | grep -vFx "$process")"
	else
		# The process is not registered.
		return 2
	fi
	
}

#
# Run all processes in an infinite loop as long as there are processes
# or until the scheduler is stopped.
#
bsda:scheduler:RoundTripScheduler.run() {
	local process processes protectedProcesses running IFS

	IFS='
'

	# Get the list of processes.
	$this.getProtectedProcesses protectedProcesses
	$this.getProcesses processes
	processes="$protectedProcesses${protectedProcesses:+${processes:+$IFS}}$processes"

	# Get the running state.
	setvar ${this}running 1

	#
	# Proceed until the list of processes is empty or the running state
	# is unset.
	#
	while [ -n "$processes" ]; do
		# Call every process.
		for process in $processes; {
			# Check the running state.
			$this.getRunning running
			test -z "$running" && return
			# Run the current process.
			$process.run
		}

		# Update the list of processes.
		$this.getProtectedProcesses protectedProcesses
		$this.getProcesses processes
		processes="$protectedProcesses${protectedProcesses:+${processes:+$IFS}}$processes"
	done
}

#
# Stop the scheduler and call the stop method of every registered process.
#
bsda:scheduler:RoundTripScheduler.stop() {
	local process processes protectedProcesses IFS
	IFS='
'

	# Stop the processing loop.
	unset ${this}running

	# Get the list of processes.
	$this.getProtectedProcesses protectedProcesses
	$this.getProcesses processes
	processes="$protectedProcesses${protectedProcesses:+${processes:+$IFS}}$processes"

	# Call every process.
	for process in $processes; {
		# Stop the current process.
		$process.stop
	}
}

