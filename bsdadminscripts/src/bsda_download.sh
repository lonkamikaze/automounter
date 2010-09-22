#!/bin/sh -f
#
# Copyright (c) 2009, 2010
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
test -n "$bsda_download" && return 0
bsda_download=1

# Include framework for object oriented shell scripting.
. ${bsda_dir:-.}/bsda_obj.sh

# Include scheduling library.
. ${bsda_dir:-.}/bsda_scheduler.sh

# Inlcude messaging library.
. ${bsda_dir:-.}/bsda_messaging.sh

#
# Offers classes to download files from a background download manager.
#

#
# The location that servers use to create message queues in.
#
: ${bsda_download_tmp="/tmp"}


# Define messages.
readonly bsda_download_MSG_TERM=0

#
# This class represents a download manager.
#
bsda:obj:createClass bsda:download:Manager \
	implements:bsda:scheduler:Process \
	w:private:scheduler \
		"An instance of bsda:scheduler:Scheduler." \
	w:private:jobQueue \
		"An instance of bsda:scheduler:ProcessQueue." \
	w:private:servers \
		"The servers to work with." \
	w:private:messenger \
		"The messenger for both processes." \
	w:private:controllerPID \
		"The process to watch. If this process dies so should the" \
		"background download manager." \
	w:private:downloaderPID \
		"The PID of the background downloading process." \
	w:private:completedJobs \
		"A list of recently completed jobs." \
	i:private:init \
		"The constructor." \
	x:private:downloader \
		"Forked off by the constructor to create the downloader" \
		"process." \
	x:private:runDownloader \
		"Called by the run method in the downloader context." \
	x:private:runController \
		"Called by the run method in the controller context." \
	x:private:send \
		"Sends data through the message queue." \
	x:protected:sendObject \
		"Sends an object through the message queue." \
	x:protected:propagate \
		"Propagates changes in the caller to the partner process." \
	x:public:createJob \
		"Creates a job and dispatches it." \
	x:public:createJobs \
		"Creates a bunch of jobs and dispatches them." \
	x:public:completedJobs \
		"Get newly completed jobs." \
	x:public:getStatus \
		"Returns a status summary from the servers." \
	x:public:term \
		"Tell the background downloader to terminate." \
	x:public:isActive \
		"Reports whether the background downloader is still available." \


#
# The constructor forks away the background downloading process and offers
# functions for download requests.
#
# @param 1
#	A Servers instance, which is used for downloading.
# @param 2
#	An optional process ID the background downloader should watch.
# @return
#	1 if the parameter 1 is not a bsda:download:Servers instance.
#
bsda:download:Manager.init() {
	# The servers list.
	bsda:download:Servers.isInstance "$1" || return 1
	setvar ${this}servers $1

	# Remember controller process ID, it's required for the background
	# downloader to terminate if the master process dies.
	if bsda:obj:isUInt "$2"; then
		setvar ${this}controllerPID $2
	fi

	# Create a message queue.
	bsda:messaging:FileSystemMessenger ${this}messenger "$bsda_download_tmp/$this"

	# Fork away the background downloader.
	$this.downloader &
	setvar ${this}downloaderPID $!
}

#
# This method is called and forked by the constructor and acts as the
# background downloader job.
#
# Once the downloader 
#
bsda:download:Manager.downloader() {
	local scheduler sleeper servers messenger jobQueue

	# Create a scheduler for the jobs.
	bsda:scheduler:RoundTripScheduler scheduler
	$this.setScheduler $scheduler
	bsda:scheduler:ProcessQueue jobs
	$this.setJobQueue $jobs

	# Make sure to die gracefully upon the usual signals.
	trap "$scheduler.stop" sigint sigterm

	# Create a sleeper job.
	bsda:scheduler:Sleep sleeper 0.5

	# Register initial jobs.
	$scheduler.register $sleeper
	$scheduler.register $this
	$scheduler.register $jobs

	# Tell the servers about the scheduler.
	$servers.setScheduler $scheduler

	# Cede control to the scheduler.
	$scheduler.run

	# The scheduler has terminated, so clean up.
	$this.getServers servers
	$servers.delete 1
	$this.getMessenger messenger
	$messenger.delete 1
	$scheduler.delete
	$sleeper.delete
	$this.delete
}

#
# The run method required by the bsda:scheduler:Process interface.
#
# It checks whether the current process is the background downloader or the
# controlling process and calls runController() or runDownloader()
# accordingly.
#
bsda:download:Manager.run() {
	local downloaderPID

	$this.getDownloaderPID downloaderPID
	if [ -z "$downloaderPID" ]; then
		$this.runDownloader
	else
		$this.runController
	fi
}

#
# Called by the run() method in the controller context.
#
# Flushes the message queue, i.e. update all Jobs.
#
bsda:download:Manager.runController() {
	local IFS messenger lines count line object jobs

	$this.getMessenger messenger
	$messenger.receive lines count

	# Nothing returned, skip the rest.
	if [ $count -eq 0 ]; then
		return 0
	fi

	IFS='
'

	$this.getCompletedJobs jobs
	for line in $lines; do
		# Deserialize objects.
		bsda:obj:deserialize object "$line"

		# Remember completed jobs.
		if bsda:download:Job.isInstance "$object"; then
			if $object.hasCompleted; then
				jobs="${jobs:+$jobs$IFS}$object"
			fi
		fi
	done
	$this.setCompletedJobs "$jobs"
}

#
# Called by the run() method in the downloader context.
#
# If a controlling process was defined, terminate the scheduler if the process
# disappeared.
# Update objects from the queue and register jobs to the scheduler.
#
bsda:download:Manager.runDownloader() {
	local IFS messenger line lines count object scheduler controllerPID
	local jobQueue

	IFS='
'

	$this.getScheduler scheduler
	# Check whether the controlling process is still present, if one was
	# specified.
	$this.getControllerPID controllerPID
	if [ -n "$controllerPID" ] && ! /bin/kill -0 "$controllerPID" 2> /dev/null; then
		$scheduler.stop
		return
	fi

	$this.getMessenger messenger
	$messenger.receive lines count

	# Nothing returned, skip the rest.
	if [ $count -eq 0 ]; then
		return 0
	fi

	$this.getJobQueue jobQueue
	for line in $lines; do
		# Deserialize objects or execute remote commands.
		bsda:obj:deserialize object "$line"

		# Queue jobs.
		if bsda:download:Job.isInstance "$object"; then
			$object.setScheduler $jobQueue
			$jobQueue.register "$object"
		fi
	done
}

#
# Required by the bsda:scheduler:Process interface.
#
# Does nothing.
#
bsda:download:Manager.stop() {
	return
}

#
# Sends data strings through the message queue.
#
# @param 1
#	The message to send.
# @return
#	1 if the message is an object or serialized object.
#	0 if everything is in order.
#
bsda:download:Manager.send() {
	local messenger
	$this.getMessenger messenger

	# Try to send the message.
	while ! $messenger.send "$1"; do
		# Flush the message queue if necessary.
		$this.run
	done
	return 0
}

#
# Sends an object through the queue. This is a multi-processing safe
# operation.
#
# @param 1
#	The object to send.
# @return
#	1 if the message is not an object.
#	0 if everything is in order.
#
bsda:download:Manager.sendObject() {
	# Check whether this is an object.
	bsda:obj:isObject "$1" || return 1

	local messenger serialized
	$this.getMessenger messenger
	$1.serialize serialized

	# Try to send the message.
	while ! $messenger.send "$serialized"; do
		# Flush the message queue if necessary.
		$this.run
		# Reserialize in case the object was changed.
		$1.serialize serialized
	done

	return 0
}

#
# Propagates the calling object to the partner process.
#
bsda:download:Manager.propagate() {
	local object
	# Get the caller.
	$caller.getObject object

	# Propagate the object to the partner process.
	$this.sendObject "$object"
}

#
# Creates a new job and forwards it to the downloading process.
#
# @param 1
#	The name of the variable to store the created job in.
# @param 2
#	The remote file name.
# @param 3
#	The local file name.
#
bsda:download:Manager.createJob() {
	local servers job
	$this.getServers servers
	# Duplicate servers object.
	$servers.copy servers

	# Create the job.
	bsda:download:Job job $this $servers "$2" "$3"
	# Return the job.
	$caller.setvar "$1" $job

	# Dispatch the job.
	$this.sendObject $servers
	$this.sendObject $job
}

#
# Creates a bunch of new job and forwards them to the downloading process.
#
# This method is faster for a high number of downloads than the createJob()
# method. The downturn is that its use is less convenient.
#
# @param 1
#	The name of the variable to store the list of created jobs in.
# @param @
#	Theremaining parameters are expected to follow the pattern:
#		<remote file> <local file> ...
#
bsda:download:Manager.createJobs() {
	local IFS servers serversCopy jobs message result messenger

	IFS='
'

	result="$1"
	shift
	$this.getServers servers
	jobs=
	while [ $# -ge 2 ]; do
		# Duplicate servers object.
		$servers.copy serversCopy
		# Create a job object.
		bsda:download:Job job $this $serversCopy "$1" "$2"
		jobs="${jobs:+$jobs$IFS}$job"
		shift 2

		# Serialize the servers and job for later delivery.
		$serversCopy.serialize serversCopy
		$job.serialize job
		# Append to the message for submission.
		message="${message:+$message$IFS}$serversCopy$IFS$job"
	done

	# Return the jobs.
	$caller.setvar "$result" "$jobs"

	# Dispatch the jobs.
	$this.getMessenger messenger
	while ! $messenger.send "$message"; do
		# Note that we only can skip reserializing here,
		# because we know that no other process has these objects
		# and thus they cannot have been changed.
		$this.run
	done
}

#
# Returns the recently completed jobs.
#
# Every completed job will only be returned once.
#
# @param &1
#	The name of the variable to hold the commpleted jobs.
# @return
#	Returns true (0) if there were any completed jobs,
#	false (1) otherwise.
#
bsda:download:Manager.completedJobs() {
	local jobs
	$this.getCompletedJobs jobs
	$this.setCompletedJobs
	$caller.setvar "$1" "$jobs"
	test -n "$jobs"
}

#
# Returns a status summary from the servers.
#
# This is a simple wrapper around Servers.getStatus().
#
# @param &1
#	The name of the variable to store the number of currently active
#	downloads in.
# @param &2
#	The number of servers the downloads are distributed over.
# @param &3
#	The number of all servers.
# @param &4
#	The involved jobs, a list of Job instances.
#
bsda:download:Manager.getStatus() {
	local servers
	$this.getServers servers
	$servers.getStatus "$@"
}

#
# Terminate the background downloader.
#
bsda:download:Manager.term() {
	local downloaderPID
	$this.getDownloaderPID downloaderPID
	/bin/kill $downloaderPID 2> /dev/null
	$this.setDownloaderPID
}

#
# Checks whether the background downloader is still available.
#
# @return
#	True (0) if the downloader is still present, else false (1).
#
bsda:download:Manager.isActive() {
	local downloaderPID
	$this.getDownloaderPID downloaderPID
	/bin/kill -0 $downloaderPID 2> /dev/null || return 1
}

#
# Instances of this class represent a download location.
#
bsda:obj:createClass bsda:download:Server \
	implements:bsda:scheduler:Process \
	w:private:free \
		"Server is free counter." \
	w:private:location \
		"The download location on the server, to which given" \
		"download paths are relative." \
	w:private:listener \
		"A message queue listener to communicate with downloads." \
	w:private:sender \
		"A message queue sender for the downloads." \
	w:private:scheduler \
	x:protected:setScheduler \
		"A bsda:scheduler:Scheduler instance." \
	w:private:downloads \
		"A list of the currently running downloads." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \
	x:protected:isAvailable \
		"Returns whether the server is available." \
	x:protected:download \
		"Downloads a file from a server." \
	x:protected:getSize \
		"Gets the size of the source file." \
	x:public:getStatus \
		"Returns the number of active downloads." \

#
# Sets up a server object.
#
# @para 1
#	The download location.
# @para 2
#	An optional count of permitted simultaneous downloads from this server,
#	if not given one is assumed.
# @return
#	0 if everything goes fine
#	1 if the given count of simultaneously permitted downloads is not an
#	  integer greater zero
#	2 if creating a messenger failed
#
bsda:download:Server.init() {
	$this.setLocation "$1"
	bsda:obj:isInt "${2:-1}" && [ "${2:-1}" -gt "0" ] || return 1
	$this.setFree "${2:-1}"
	$this.setDownloads
	bsda:messaging:FileSystemListener ${this}listener "$bsda_download_tmp/$this" || return 2
	bsda:messaging:FileSystemSender ${this}sender "$bsda_download_tmp/$this" || return 2
}

#
# The destructor deletes the contained listener and sender objects and the
# files created by them.
#
bsda:download:Server.clean() {
	local IFS sender listener downloads

	IFS='
'

	# Kill all downloads.
	downloads="$($this.getDownloads | /usr/bin/sed 's,.*:,,')"
	if [ -n "$downloads" ]; then
		/bin/kill $downloads 2> /dev/null
		$this.setDownloads
	fi

	# Delete sender and listener.
	$this.getSender sender
	$this.getListener listener
	$sender.delete
	# Also delete the queue.
	$listener.delete 1
	return 0
}

#
# Checks whether the server is available.
#
# @return
#	0 if the server is available
#	1 if the server is not available
#
bsda:download:Server.isAvailable() {
	local free
	$this.getFree free
	test $free -gt 0
}

#
# Tries to download the calling job.
#
# @return
#	0 for a successful download
#	1 if the caller is not a job
#	2 if the server is not available
#	3 for a failed download
#
bsda:download:Server.download() {
	local job downloads IFS free manager scheduler
	IFS='
'

	$caller.getObject job
	# Quit if the caller is not a job.
	bsda:download:Job.isInstance "$job" || return 1
	# Quit if the server is not available.
	$this.isAvailable || return 2

	# Register at the scheduler.
	$this.getScheduler scheduler
	$scheduler.register

	# Get the list of currently running downloads.
	$this.getDownloads downloads

	# The following block gets forked away, so nothing has to be declared
	# local.
	(
		# Don't let fetch block signals.
		#
		# The -T parameter activates asynchronous signal handling,
		# which means a signal is trapped immediately, no matter which
		# command is currently executed. Otherwise kill signals would
		# be acted upon only after the currently active command
		# completes. This is most likely fetch and thus takes too long.
		#
		# The -T parameter is dangerous, do not mess with it unless
		# you know what is safe to do.
		set -T
		trap 'kill $(jobs -s) 2> /dev/null; exit 1' sigint sigterm

		$this.getSender sender
		$this.getLocation location
		$job.getSource source
		$job.getTarget target
		if ! $job.getSize size; then
			# If getting the size did not succeed, it has to be
			# assumed that the file does not exist. Thus instantly
			# report failure.
			$sender.send "action=end;job=$job;status=1;time=;"
			return
		fi
		# Report begin of download.
		time=$(/bin/date -u +%s)
		$sender.send "action=start;job=$job;size=$size;time=$time;"

		# Synchronize the file with the server.
		/usr/bin/fetch -qmS "$size" -o "$target" "$location/$source" > /dev/null 2>&1
		result=$?

		# Report the download result.
		time=$(/bin/date -u +%s)
		$sender.send "action=end;job=$job;status=$result;time=$time;"
	) &
	# Append the new download.
	downloads="${downloads:+$downloads$IFS}$job:$!"
	$this.setDownloads "$downloads"

	# Update the amount of available download slots.
	$this.getFree free
	$this.setFree $((free - 1))

	return 0
}

#
# Returns the size of the file on the server seeked by the calling job.
#
# @param &1
#	The name of the variable to return the size to.
# @return
#	0 if everything goes fine
#	1 if the caller is not a job.
#	2 if the size was not acquired
#
bsda:download:Server.getSize() {
	local size job source location

	$caller.getObject job
	# Quit if the caller is not a job.
	bsda:download:Job.isInstance "$job" || return 1

	# Get the file to return the size of.
	$job.getSource source

	# Get the download location.
	$this.getLocation location

	# Get the file size from this server.
	if ! size="$(/usr/bin/fetch -s "$location/$source" 2> /dev/null)"; then
		if ! size="$(/usr/bin/fetch -s "$location/$source" 2> /dev/null)"; then
			$caller.setvar "$1"
			return 2
		fi
	fi

	# Unknown size is not supported.
	if [ "$size" = "Unknown" ]; then
		$caller.setvar "$1"
		return 2
	fi

	# Return the size.
	$caller.setvar "$1" "$size"
}

#
# Returns the number of active downloads and the jobs.
#
# @param 1
#	The name of the variable to store the number of currently active
#	downloads in.
# @param 2
#	The running jobs.
#
bsda:download:Server.getStatus() {
	local downloads
	$this.getDownloads downloads
	$caller.setvar "$1" $(($(echo "$downloads" | /usr/bin/wc -w)))
	$caller.setvar "$2" "$(echo "$downloads" | /usr/bin/sed 's/:.*//')"
}

#
# Check download status and unregister if all downloads have been processed.
# Register jobs that have been completed back to the scheduler.
# That only works when called by a scheduler.
#
bsda:download:Server.run() {
	local message messages download job status downloads listener count
	local IFS scheduler free size manager action time

	IFS='
'

	# Get the list of currently running downloads.
	$this.getDownloads downloads

	# Get the latest messages.
	$this.getListener listener
	$listener.receive messages count

	# No need to continue if there were no messages.
	if [ "$count" -eq "0" ]; then
		return 0
	fi

	# Get the scheduler.
	$this.getScheduler scheduler

	# Go through all messages.
	manager=
	for message in $messages; do
		# The message contains the action and other variables.
		eval "$message"

		case "$action" in
		start)
			# The message contained: job, time, size

			# Update the job.
			$job.setStartDownloadTime $time
			$job.setEndDownloadTime
			$job.setSize $size
		;;
		end)
			# The message contained: job, time, status

			# Update the job.
			$job.setEndDownloadTime $time

			# Update the amount of free download slots.
			$this.getFree free
			$this.setFree $((free + 1))

			# Update the list of downloads.
			downloads="$(echo "$downloads" | /usr/bin/grep -vF "$job:")"

			# Store the update downloads list.
			$this.setDownloads "$downloads"

			# Notify the job.
			if [ "$status" -eq "0" ]; then
				$job.downloadSucceeded
			else
				$job.downloadFailed
			fi
		;;
		esac

		# Notify the controlling process of changes.
		$job.getManager manager
		$manager.sendObject $job
		$manager.propagate

		# If a job has completed it is no longer required in the
		# downloader context.
		if $job.hasCompleted; then
			$job.delete
		fi
	done

	# Unregister from the scheduler if all downloads have been completed.
	if [ -z "$downloads" ]; then
		# Unregister from the scheduler.
		$scheduler.unregister
	fi
}

#
# Kill all downloads.
#
bsda:download:Server.stop() {
	local IFS downloads
	
	IFS='
'

	# Get the list of currently running downloads and kill them all.
	downloads="$($this.getDownloads | /usr/bin/sed 's,.*:,,')"
	if [ -n "$downloads" ]; then
		/bin/kill $downloads 2> /dev/null
		$this.setDownloads
	fi
}


#
# Represents a list of servers, divided into mirrors and a master server.
#
bsda:obj:createClass bsda:download:Servers \
	w:private:master \
		"The master server." \
	x:protected:getMaster \
		"Change access scope of the getter." \
	w:private:mirrors \
		"A list of mirror servers." \
	x:protected:mirrorsLeft \
		"Returns whether there are still mirrors left." \
	x:protected:popMirror \
		"Pops a free server from the list." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \
	x:protected:setScheduler \
		"Forward a bsda:scheduler:Scheduler instance to all servers." \
	x:public:getStatus \
		"Returns the number of active downloads." \


#
# The constructor takes a list of servers.
#
# @param 1
#	The master server.
# @param @
#	All following server instances are objects.
# @return
#	0 if everything goes fine
#	1 if the master service is not a bsda:download:Server instance
#	2 if one of the mirrors is not a bsda:download:Server instance
#
bsda:download:Servers.init() {
	local IFS mirrors

	IFS='
'

	# Check and store the master.
	bsda:download:Server.isInstance "$1" || return 1
	$this.setMaster "$1"

	# Check and store the mirrors.
	mirrors=
	while [ -n "$2" ]; do
		bsda:download:Server.isInstance "$2" || return 2
		mirrors="${mirrors:+$mirrors$IFS}$2"
		shift
	done
	$this.setMirrors "$mirrors"
}

#
# The destructor, deletes all the registered servers on request.
#
# @param 1
#	If set all the Server instances are deleted, too.
#
bsda:download:Servers.clean() {
	local IFS mirror

	IFS='
'

	# Return if the servers are not to be deleted.
	test -z "$1" && return 0

	$this.getMaster mirror
	$mirror.delete

	for mirror in $($this.getMirrors); do
		$mirror.delete
	done
	return 0
}

#
# Returns whether mirrors are left.
#
# @return
#	0 if there are mirrors in the list
#	1 if the list of mirrors is empty
#
bsda:download:Servers.mirrorsLeft() {
	test -n "$($this.getMirrors)"
}

#
# Tries to pop a free mirror from the list of mirros.
#
# @para 1
#	The name of the variable to store the mirror in.
# @return
#	0 if a mirror was returned
#	1 if no mirror is currently available
#	2 if the list of mirrors is empty
#
bsda:download:Servers.popMirror() {
	local IFS mirrors mirror

	IFS='
'

	$this.mirrorsLeft || return 2

	# Try to return a free mirror.
	$this.getMirrors mirrors
	for mirror in $mirrors; do
		if $mirror.isAvailable; then
			# Return the mirror.
			$caller.setvar "$1" "$mirror"
			# Remove the returned mirror from the list.
			mirrors="$(echo "$mirrors" | /usr/bin/grep -vFx "$mirror")"
			$this.setMirrors "$mirrors"
			# Terminate.
			return 0
		fi
	done

	# No mirror was available, return nothing.
	$caller.setvar "$1"
	return 1
}

#
# Forwards a scheduler to every server object.
#
# @param 1
#	The scheduler to forward.
# @return
#	Returns false (1) if the given parameter is not a scheduler,
#	else true (0).
#
bsda:download:Servers.setScheduler() {
	local IFS mirror

	IFS='
'

	# Only forward schedulers.
	if ! bsda:scheduler:Scheduler.isInstance "$1"; then
		return 1
	fi

	$this.getMaster mirror
	$mirror.setScheduler "$1"

	for mirror in $($this.getMirrors); do
		$mirror.setScheduler "$1"
	done
	return 0
}

#
# Returns the sum of active downloads over all servers.
#
# @param &1
#	The name of the variable to store the number of currently active
#	downloads in.
# @param &2
#	The number of servers the downloads are distributed over.
# @param &3
#	The number of all servers.
# @param &4
#	The involved jobs, a list of Job instances.
#
bsda:download:Servers.getStatus() {
	local IFS sum servers active mirrors mirror jobs job

	IFS='
'

	# Get the active master downloads.
	$this.getMaster mirror
	$mirror.getStatus sum jobs
	servers=1
	active=0
	test $sum -gt 0 && active=1

	# Get the active mirror downloads.
	$this.getMirrors mirrors
	for mirror in $mirrors; do
		servers=$((servers + 1))
		$mirror.getStatus mirror job
		jobs="${jobs:+$jobs${job:+$IFS}}$job"
		sum=$((sum + mirror))
		test $mirror -gt 0 && active=$((active + 1))
	done

	$caller.setvar "$1" $sum
	$caller.setvar "$2" $active
	$caller.setvar "$3" $servers
	$caller.setvar "$4" "$jobs"
}

#
# Represents a download job.
#
bsda:obj:createClass bsda:download:Job \
	implements:bsda:scheduler:Process \
	w:private:success \
		"Whether the job was successfully completed." \
	w:private:scheduler \
	x:protected:setScheduler \
		"A bsda:scheduler:Scheduler instance." \
	w:private:source \
		"The download source file name." \
	x:protected:getSource \
		"Adjust access to the getter method." \
	w:private:target \
	x:public:getTarget \
		"The local target location." \
	w:protected:size \
		"The download size." \
	w:protected:startDownloadTime \
		"The time a download attempt started." \
	w:protected:endDownloadTime \
		"The time a download attempt completed." \
	w:private:servers \
		"A Servers instance that is used as a queue for untried" \
		"download mirrors." \
	w:private:manager \
	x:protected:getManager \
		"The download manager instance." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \
	x:protected:downloadSucceeded \
		"Called by a server if a download succeeded." \
	x:protected:downloadFailed \
		"Called by a server if a download failed." \
	x:public:hasCompleted \
		"Returns whether the download was completed." \
	x:public:hasSucceeded \
		"Returns whether the download has succeeded." \
	x:public:getStatus \
		"Returns the current job status." \

#
# The constructor initializes attributes.
#
# @param 1
#	The download manager instance.
# @param 2
#	A Servers instance to pull the download servers from.
# @param 3
#	The remote file name.
# @param 4
#	The local file name.
# @return
#	0 if everything goes fine
#	1 if the fisrt parameter is not a Manager instance
#	2 if the second parameter is not a Servers instance
#
bsda:download:Job.init() {
	# Check whether the first parameter is a Manager instance.
	bsda:download:Manager.isInstance "$1" || return 1
	# Check whether the second parameter is a Servers instance.
	bsda:download:Servers.isInstance "$2" || return 2

	# Store attributes.
	$this.setManager "$1"
	$this.setServers "$2"
	$this.setSource "$3"
	$this.setTarget "$4"
}

#
# The destructor removes the list of servers.
#
bsda:download:Job.clean() {
	local servers
	$this.getServers servers

	# Delete the list of servers if one is there (might not be the case
	# if the constructor failed).
	if bsda:download:Servers.isInstance "$servers"; then
		$servers.delete
	fi
	return 0
}

#
# A getter for the file size.
#
# This overwrites the auto-generated getter method.
#
# @param &1
#	The variable to return the size to.
# @return
#	Returns true (0) if the size is returned, false (1) otherwise.
#
bsda:download:Job.getSize() {
	local size servers master

	# Get the size.
	bsda:obj:getVar size ${this}size
	# Check whether the size is already known.
	if [ -n "$size" ]; then
		# Return the size.
		$caller.setvar "$1" "$size"
		return 0
	fi

	# The size is not yet known, so acquire it.
	$this.getServers servers
	$servers.getMaster master
	if ! $master.getSize size; then
		$caller.setvar "$1"
		return 1
	fi
		

	# Store the size.
	setvar ${this}size "$size"

	# Return the size.
	$caller.setvar "$1" "$size"
	return 0
}

#
# This checks for available mirrors and dispatches a download if one is
# available. In that case the Job unregisters itself from the scheduler
# and registers the downloading server instead.
#
# Should the download have already completeted, this job unregisters
# itself.
#
bsda:download:Job.run() {
	local success scheduler servers mirror manager size

	$this.getScheduler scheduler

	# If we already completed immediately unregister.
	if $this.hasCompleted; then
		$scheduler.unregister
		return
	fi

	# Check whether there are mirrors available.
	$this.getServers servers
	mirror=
	if $servers.mirrorsLeft; then
		# Try to get a free mirror.
		$servers.popMirror mirror
	else
		# Try to use the master server.
		$servers.getMaster mirror
		if ! $mirror.isAvailable; then
			mirror=
		fi
	fi

	# If a mirror is available, dispatch a download.
	if [ -n "$mirror" ]; then
		# Start a download.
		if $mirror.download; then
			# Unregister from the scheduler.
			$scheduler.unregister
		fi
	fi
}

#
# This is required by the bsda:scheduler:Process interface and does nothing.
#
bsda:download:Job.stop() {
	return
}

#
# This is called by a Server instance after it successfully completed a
# download for this job.
#
bsda:download:Job.downloadSucceeded() {
	local servers manager

	# Delete the list of servers.
	$this.getServers servers
	$servers.delete
	$this.setServers

	# Store the success of this job.
	$this.setSuccess 0
}

#
# This is called by a Server instance after it failed to complete a
# download for this job.
#
# The method checks whether the caller (failing Server) was the master
# server. In that case the job is cleaned up and the method terminates.
#
# Otherwise the Job is reregistered at the scheduler.
#
bsda:download:Job.downloadFailed() {
	local servers mirror master scheduler manager

	# Get the mirror and the master server.
	$caller.getObject mirror
	$this.getServers servers
	$servers.getMaster master

	# Check whether the failed mirror was the master server.
	if [ "$master" = "$mirror" ]; then
		# The download from the master server failed. Time to give up.

		# Delete the list of servers.
		$servers.delete
		$this.setServers

		# Store success status (failed).
		$this.setSuccess 1
	else
		# Reregister at the scheduler.
		$this.getScheduler scheduler
		$scheduler.register
	fi
}

#
# Returns whether the job has been completed.
#
# @return
#	0 if the job has been completed
#	1 otherwise
#
bsda:download:Job.hasCompleted() {
	test -n "$($this.getSuccess)"
}

#
# Returns whether the job has succeeded.
#
# @return
#	0 if the job has succeeded
#	1 otherwise
#
bsda:download:Job.hasSucceeded() {
	$this.hasCompleted || return 1
	local success
	$this.getSuccess success
	return $success
}

#
# Returns a bunch of status information.
#
# @param 1
#	The variable to store the local target file name in.
# @param 2
#	The variable to for the current file size (bytes) of the download.
# @param 3
#	The variable for the full file size in bytes.
# @param 4
#	The variable for the number of seconds passed downloading.
# @param 5
#	The variable for the expected number of seconds left downloading.
# @param 6
#	The variable for the progress in %.
# @param 7
#	The variable for the average download speed in bytes/second.
# @return
#	0 (true) if the download is in progress, 1 otherwise.
#
bsda:download:Job.getStatus() {
	local status size start end passed
	local  target realsize progress speed predict

	$this.getSize size
	$this.getStartDownloadTime start
	$this.getEndDownloadTime end
	$this.getTarget target

	#
	# Two cases the download is in progress/completed or has not yet
	# started.
	#
	if [ -n "$start" ]; then
		# A download is in progress or has started.

		# Get the current file size, assume at least 1 byte.
		realsize=$(wc -c "$target" 2> /dev/null)
		realsize=${realsize% *}
		test $((realsize)) -eq 0 && realsize=1

		# The download has not yet completed, so we use NOW to
		# calculate progress and speed.
		if [ -z "$end" ]; then
			end=$(/bin/date -u +%s)
		fi

		# The time passed in seconds, at least 1.
		passed=$((end - start))
		test $((passed)) -eq 0 && passed=1

		# The progress in %.
		progress=$((realsize * 100 / size))

		# The average speed in bytes/second.
		speed=$((realsize / passed))

		# Seconds left, add a 10% 'bonus' to the prediction for safety.
		predict=$(((passed * size / realsize - passed) * 11 / 10))
	else
		# No progress.
		realsize=0
		passed=0
		progress=0
		speed=0
		predict=0
	fi

	# Return all the results
	$caller.setvar "$1" "$target"
	$caller.setvar "$2" $realsize
	$caller.setvar "$3" $size
	$caller.setvar "$4" $passed
	$caller.setvar "$5" $predict
	$caller.setvar "$6" $progress
	$caller.setvar "$7" $speed

	# Return whether the download is currently in progress.
	return $status
}

