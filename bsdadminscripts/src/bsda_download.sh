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
	w:private:servers \
		"The servers to work with." \
	w:private:messenger \
		"The messenger for both processes." \
	w:private:controllerPID \
		"The process to watch. If this process dies so should the" \
		"background download manager." \
	w:private:downloaderPID \
		"The PID of the background downloading process." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \
	x:private:downloader \
		"Forked off by the constructor to create the downloader" \
		"process." \
	x:private:runDownloader \
		"Called by the run method in the downloader context." \
	x:private:runController \
		"Called by the run method in the controller context." \
	x:private:send \
		"Sends data through the message queue." \
	x:protected:propagate \
		"Propagates changes in the caller to the partner process." \
	x:public:createJob \
		"Creates a job and dispatches it." \
	x:public:term \
		"Tell the background downloader to terminate." \


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

bsda:download:Manager.clean() {
	return
}

bsda:download:Manager.downloader() {
	local scheduler sleeper servers messenger

	# Create a scheduler for the jobs.
	bsda:scheduler:RoundTripScheduler scheduler

	# Create a sleeper job.
	bsda:scheduler:Sleep sleeper 0.5

	# Register initial jobs.
	$scheduler.register $sleeper
	$scheduler.register $this

	# Cede control to the scheduler.
	$scheduler.run

	# The scheduler has terminated, so clean up.
	$this.getServers servers
	$servers.delete 1
	$this.getMesssenger messenger
	$messenger.delete 1
	$scheduler.delete
	$sleeper.delete
	$this.delete
}

bsda:download:Manager.run() {
	local downloaderPID

	$this.getDownloaderPID downloaderPID

	if [ -z "$downloaderPID" ]; then
		$this.runDownloader
	else
		$this.runController
	fi
}

bsda:download:Manager.runController() {
	local messenger lines count

	$this.getMesssenger messenger
	$messenger.receive lines count
	eval "$lines"
}

bsda:download:Manager.runDownloader() {
	local IFS messenger line lines count object scheduler controllerPID

	IFS='
'

	$this.getScheduler scheduler
	# Check whether the controlling process is still present, if one was
	# specified.
	$this.getControllerPID controllerPID
	if [ -n "$controllerPID" ] && ! kill -0 "$controllerPID"; then
		$scheduler.stop
		return
	fi

	$this.getMesssenger messenger
	$messenger.receive lines count
	for line in $lines; do
		# Deserialize objects or execute remote commands.
		bsda:obj:deserialize object "$line"

		# Queue jobs.
		if bsda:download:Job.isInstance "$object"; then
			$scheduler.register "$object"
			continue
		fi
	done
}

bsda:download:Manager.stop() {
	return
}

#
# @param 1
#	The message to send.
#
bsda:download:Manager.send() {
	local messenger
	$this.getMesssenger messenger

	# Try to send the message.
	while ! $messenger.send "$1"; do
		# Flush the message queue if necessary.
		$this.run
	done
}

bsda:download:Manager.propagate() {
	local object
	# Serialize the caller.
	$caller.getObject object
	$object.serialize object

	# Propagate the object to the partner process.
	$this.send "$object"
}

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
	$caller.setvar $job

	# Serialize servers and job.
	$servers.serialize servers
	$job.serialize job

	# Dispatch the job.
	$this.send "$servers"
	$this.send "$job"
}

#
# Terminate the background downloader.
#
bsda:download:Manager.term() {
	$this.send '$scheduler.stop'
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
	local sender listener download

	# Kill all downloads.
	for download in $($this.getDownloads); do
		kill -TERM $download
	done

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
	local job downloads IFS free manager
	IFS='
'

	$caller.getObject job
	# Quit if the caller is not a job.
	bsda:download:Job.isInstance "$job" || return 1
	# Quit if the server is not available.
	$this.isAvailable || return 2

	# Get the list of currently running downloads.
	$this.getDownloads downloads

	# The following block gets forked away, so nothing has to be declared
	# local.
	(
		$this.getSender sender
		$this.getLocation location
		$job.getSource source
		$job.getTarget target
		$job.getSize size
		fetch -qmS "$size" -o "$target" "$location/$source" > /dev/null 2>&1
		result=$?
		$sender.send "download=$$;job=$job;status=$result;size=$size"
	) &
	# Update the amount of available download slots.
	$this.getFree free
	$this.setFree $(($free - 1))

	# Append the new download.
	downloads="${downloads:+$downloads$IFS}$!"
	$this.setDownloads "$downloads"

	# Propagate changes to the controlling process.
	$job.getManager manager
	$manager.propagate
}

#
# Returns the size of the file on the server seeked by the calling job.
#
# @param 1
#	The name of the variable to return the size to.
# @return
#	0 if everything goes fine
#	1 if the caller is not a job.
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

	# Get the file from this server.
	size="$(fetch -s "$location/$source" 2> /dev/null)"

	# Return the size.
	$caller.setvar "$1" "$size"
}

#
# Check download status and unregister if all downloads have been processed.
# Register jobs that have been completed back to the scheduler.
# That only works when called by a scheduler.
#
bsda:download:Server.run() {
	local message messages download job status downloads listener count
	local IFS scheduler free size manager

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

	# Update the amount of free download slots.
	$this.getFree free
	free=$(($free + $count))
	$this.setFree $free


	# Unregister from the scheduler if all downloads have been completed.
	if [ -z "$downloads" ]; then
		# Get the scheduler.
		$caller.getObject scheduler
		# Ceck whether this was called by a scheduler.
		if bsda:scheduler:Scheduler.isInstance "$scheduler"; then
			# Unregister from the scheduler.
			$scheduler.unregister
		fi
	fi

	# Go through all messages.
	for message in $messages; do
		# The message contains download, job, status and size.
		eval "$message"

		# Update the list of downloads.
		downloads="$(echo "$downloads" | grep -vx "$download")"
		$this.setDownloads "$downloads"

		# Tell the download size to the job.
		$job.setSize "$size"

		# Notify the controlling process.
		$job.getManager manager
		$manager.propagate

		# Notify the job.
		if [ "$status" -eq "0" ]; then
			$job.downloadSucceeded
		else
			$job.downloadFailed
		fi
	done
}

#
# Kill all downloads.
#
bsda:download:Server.stop() {
	local IFS downloads
	
	IFS='
'

	# Get the list of currently running downloads.
	$this.getDownloads downloads

	if [ -z "$downloads" ]; then
		return 0
	fi

	# Kill all downloads.
	kill -TERM $downloads
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

	# Return if the servers are not to be deleted.
	test -z "$1" && return 0

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
			mirrors="$(echo "$mirrors" | grep -vFx "$mirror")"
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
# Represents a download job.
#
bsda:obj:createClass bsda:download:Job \
	implements:bsda:scheduler:Process \
	w:private:success \
		"Whether the job was successfully completed." \
	w:private:scheduler \
		"A bsda:scheduler:Scheduler instance." \
	w:private:source \
		"The download source file name." \
	x:protected:getSource \
		"Adjust access to the getter method." \
	w:private:target \
		"The local target location." \
	x:public:getTarget \
		"Adjust access to the getter method." \
	w:protected:size \
		"The download size." \
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
# This overwrites the auto-generated getter method and it's actually a
# performance hack. A background job normally requests it in
# Server.download().
# This download job will then send the value back to the server when
# it completes and it gets collected by Server.run(), which will call
# Job.setSize().
#
# @param 1
#	The variable to return the size to.
#
bsda:download:Job.getSize() {
	local size servers master

	# Get the size.
	$this.getSize size
	# Check whether the size is already known.
	if [ -n "$size" ]; then
		# Return the size.
		$caller.setvar "$1" "$size"
		return 0
	fi

	# The size is not yet known, so acquire it.
	$this.getServers servers
	$servers.getMaster master
	$master.getSize size

	# Store the size.
	setvar ${this}size "$size"

	# Return the size.
	$caller.setvar "$1" "$size"
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
	local success scheduler servers mirror manager

	# Update the scheduler.
	$caller.getObject scheduler
	if bsda:scheduler:Scheduler.isInstance "$scheduler"; then
		$this.setScheduler $scheduler
	else
		scheduler=
	fi

	# If we already completed immediately unregister.
	$this.getSuccess success
	if [ -n "$success" ]; then
		test -n "$scheduler" && $scheduler.unregister
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
		# Unregister from the scheduler.
		test -n "$scheduler" && $scheduler.unregister
		# Start a download.
		$mirror.download
		# Register the download to the scheduler.
		test -n "$scheduler" && $scheduler.register $mirror

		# Propagate the changed state to the controlling process.
		$this.getManager manager
		$manager.propagate
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

	# Propagate the changed state to the controlling process.
	$this.getManager manager
	$manager.propagate
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

		# Store success status (failed).
		$this.setSuccess 1
	else
		# Reregister at the scheduler.
		$this.getScheduler scheduler
		bsda:scheduler:Scheduler.isInstance "$scheduler" && $scheduler.register
	fi

	# Propagate the changed state to the controlling process.
	$this.getManager manager
	$manager.propagate
}

#
# Retursn whether the job has been completed.
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


