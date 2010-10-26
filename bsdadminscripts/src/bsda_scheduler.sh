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
. ${bsda_dir:-.}/bsda_obj.sh

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
	extends:bsda:scheduler:Process \
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
# Note that the time between successive sleep calls should be short enough to
# ensure that a PID does not get reused. This is relevant when serializing
# and reusing a Sleep instance - call the stop() method before doing so.
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
# Puts the sleeper back into a safe state.
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
	r:private:running \
		"The state of the scheduler." \
	w:private:processes \
		"The list of processes."

#
# Registers a process. If no process is given, the caller is registered.
#
# Every job can only be registered once.
#
# @param 1
#	An instance of bsda:scheduler:Process, if not given the calling
#	object is registered.
# @return
#	0 if everything goes fine or the process is already registered
#	1 if the given object is not a process
#
bsda:scheduler:RoundTripScheduler.register() {
	local IFS processes process

	IFS='
'

	# Get the list of processes.
	$this.getProcesses processes

	# Check whether a parameter was given.
	if [ -n "$1" ]; then
		process="$1"
	else
		# Get the caller.
		$caller.getObject process
	fi

	# Only accept processes.
	bsda:scheduler:Process.isInstance "$process" || return

	# Skip already registered processes.
	echo "$processes" | /usr/bin/grep -qFx "$process" && return

	# Add process to the schedule.
	$this.setProcesses "${processes:+$processes$IFS}$process"
	return 0
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
	if $this.getProcesses | /usr/bin/grep -qFx "$process"; then
		setvar ${this}processes "$($this.getProcesses | /usr/bin/grep -vFx "$process")"
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
	local process processes running IFS

	IFS='
'

	# Get the list of processes.
	$this.getProcesses processes

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
		$this.getProcesses processes
	done
}

#
# Stop the scheduler and call the stop method of every registered process.
#
bsda:scheduler:RoundTripScheduler.stop() {
	local process processes IFS
	IFS='
'

	# Stop the processing loop.
	unset ${this}running

	# Get the list of processes.
	$this.getProcesses processes

	# Call every process.
	for process in $processes; {
		# Stop the current process.
		$process.stop
	}
}

#
# Instances of this class can be used as a container for serveral processes
# in a scheduler.
#
# Every time this container is called, it will run only one of the contained
# processes, cycling through them with every call.
#
bsda:obj:createClass bsda:scheduler:ProcessQueue \
	extends:bsda:scheduler:RoundTripScheduler

#
# Runs a single job from the queue.
#
bsda:scheduler:ProcessQueue.run() {
	local process processes IFS

	IFS='
'

	# Get the list of processes.
	$this.getProcesses processes

	#
	# Proceed until the list of processes is empty or the running state
	# is unset.
	#
	if [ -n "$processes" ]; then
		# Circle the process to the end of the queue if there are
		# more than one.
		process="${processes%%${IFS}*}"
		if [ "$process" != "$processes" ]; then
			# Update the list of processes.
			$this.setProcesses "${processes#$process$IFS}$IFS$process"
		fi

		# Call the first process after the circling.
		# Thus the process does not magically reappear if it
		# unregisters.
		$process.run
	fi
}

