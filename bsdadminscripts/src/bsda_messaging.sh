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
test -n "$bsda_messaging" && return 0
bsda_messaging=1

# Include framework for object oriented shell scripting.
. bsda_obj.sh

#
# Offers classes to exchange character lines between processes.
#

#
# The following is a list of all classes and interfaces:
#	bsda:messaging:Listener		Listener interface
#	bsda:messaging:Messenger	Messenger interface
#	bsda:messaging:Lock		Read/Write file system locking class
#	bsda:messaging:FileSystemListener
#					Listener operating on a regular file
#	bsda:messaging:FileSystemMessenger
#					Messenger operating on a regular file
#





#
# An interface for listeners.
#
bsda:obj:createInterface bsda:messaging:Listener \
	x:receive \
		"Receives data from a sourcex" \
	x:receiveLine \
		"Receives a single line of data." \

#
# An interface for senders.
#
bsda:obj:createInterface bsda:messaging:Sender \
	x:send \
		"Sends data." \

#
# An interface for messengers. Note that unlike a raw sender a messanger
# needs to make sure that all data has been received, before a message is
# sent.
#
bsda:obj:createInterface bsda:messaging:Messenger \
	extends:bsda:messaging:Listener \
	extends:bsda:messaging:Sender \

#
# Instances of this class offer read and write locks to a file.
#
bsda:obj:createClass bsda:messaging:Lock \
	w:private:lock \
		"The file to use for locking." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The cleanup method." \
	x:public:lockRead \
		"Set this lock to forbid reading." \
	x:public:unlockRead \
		"Allow reading." \
	x:public:lockWrite \
		"Set this lock to forbid writing." \
	x:public:unlockWrite \
		"Allow writing."

#
# The constructor initializes attributes.
#
# @param 1
#	The file to lock.
# @return
#	1 if the lock cannot be acquired.
#
bsda:messaging:Lock.init() {
	$this.setLock "$1"
	lockf -ks "$1" sh -c "test -n \"\$(cat '$1' 2> /dev/null)\" || echo 0 > '$1'; chmod 0600 '$1'" || return 1
}

#
# Remove the lock file. If it is safe to do so.
#
bsda:messaging:Lock.clean() {
	local lock
	$this.getLock lock

	lockf -k "$lock" sh -c "
		lock=\"\$(cat '$lock')\"
		test \${lock:-0} -eq 0 && rm '$lock'
	"
}

#
# Forbid reading from the file.
#
# To lock reading the lock value has to be 0 and will be set to -1.
# Reading may only be locked once .
#
bsda:messaging:Lock.lockRead() {
	local lock
	$this.getLock lock

	# run until the lock is acquired.
	while true; do
		# Get a file system lock on the lock file.
		lockf -k "$lock" sh -c "
			lock=\"\$(cat '$lock')\"
			if [ \${lock:-0} -eq 0 ]; then
				echo -1 > '$lock'
				exit 0
			fi
			exit 1
		" && return 0
		sleep 0.01
	done
}

#
# Allow reading.
#
# Set the lock value back from -1 to 0.
#
# This does not check whether the lock was actually acquired, this simply
# is assumed.
#
bsda:messaging:Lock.unlockRead() {
	local lock
	$this.getLock lock

	# Get a file system lock on the lock file.
	lockf -k "$lock" sh -c "echo 0 > '$lock'" && return 0
}

#
# Forbid writing to the file.
#
# To lock writing the lock value has to be 0 or greater and will be increased.
# This means that several processes at once may forbid writing (in order to
# read from the file) and only when all of these locks are undone, writing
# is possible, again.
#
bsda:messaging:Lock.lockWrite() {
	local lock
	$this.getLock lock
	locked=

	# run until the lock is acquired.
	while true; do
		# Get a file system lock on the lock file.
		lockf -k "$lock" sh -c "
			lock=\"\$(cat '$lock')\"
			if [ \${lock:-0} -ge 0 ]; then
				echo \$((\${lock:-0} + 1)) > '$lock'
				exit 0
			fi
			exit 1
		" && return 0
		sleep 0.01
	done
}

#
# Allow writing to the file.
#
# Undo the lock value increment. If all of these have been undone, acquiring
# a lock for writing becomes possible again.
#
# This does not check whether the lock was actually acquired, this simply
# is assumed.
#
bsda:messaging:Lock.unlockWrite() {
	local lock
	$this.getLock lock

	# Get a file system lock on the lock file.
	lockf -k "$lock" sh -c "echo \$((\$(cat '$lock') - 1)) > '$lock'"
}


#
# A listener on a file system message queue for read only access.
#
bsda:obj:createClass bsda:messaging:FileSystemListener \
	implements:bsda:messaging:Listener \
	r:private:lock \
		"A Lock instance." \
	r:private:queue \
		"The queue file." \
	r:private:position \
		"The line number of the last received message." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \

#
# The constructor checks whether the message queue is available.
#
# @param 1
#	The file name of the message queue.
# @return
#	0 if everything goes fine
#	1 if creating a locking object fails
#
bsda:messaging:FileSystemListener.init() {
	lockf -ks "$1" chmod 0600 "$1" || return 1
	bsda:messaging:Lock ${this}lock "$1.lock" || return 1
	setvar ${this}queue "$1"
	setvar ${this}position 0
}

#
# The destructor deletes the queue and the lock.
#
# @param 1
#	If set the queue is deleted.
#
bsda:messaging:FileSystemListener.clean() {
	local lock queue
	$this.getLock lock
	$this.getQueue queue

	$lock.delete
	test -n "$1" && rm "$queue"
	return 0
}

#
# Returns all unread lines from the message queue.
#
# @param 1
#	The name of the variable to store the received lines in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:FileSystemListener.receive() {
	local IFS position queue result lines lock
	IFS='
'

	$this.getLock lock
	$this.getPosition position
	$this.getQueue queue

	# Forbid writing to the file.
	$lock.lockWrite

	# Read and append an empty line saving postfix.
	result="$(
		awk "NR > $position END {print \"EOF\"}" "$queue"
	)"

	# Permit writing to the file.
	$lock.unlockWrite

	# Get the mumber lines read. Because wc -l never returns 0, the
	# postfix helps us distuinguish between 1 and 0 lines.
	lines=$(($(echo "$result" | wc -l) - 1))

	# Update position.
	setvar ${this}position $(($position + $lines))

	# Remove postfix.
	if [ $lines -gt 0 ]; then
		result="${result%${IFS}EOF}"
	else
		result=
	fi

	# Return the resulting lines.
	$caller.setvar "$1" "$result"
	$caller.setvar "$2" "$lines"
}

#
# Returns a single line from the message queue.
#
# @param 1
#	The name of the variable to store the received line in.
# @param 2
#	The variable to store number of lines received in.
#
bsda:messaging:FileSystemListener.receiveLine() {
	local IFS position queue result lines lock
	IFS='
'

	$this.getLock lock
	$this.getPosition position
	$this.getQueue queue

	# Forbid writing to the file.
	$lock.lockWrite

	# Read a line and append an empty line saving postfix.
	result="$(
		awk "NR == $position + 1 END {print \"EOF\"}" "$queue"
	)"

	# Permit writing to the file.
	$lock.unlockWrite

	# Get the mumber lines read. Because wc -l never returns 0, the
	# postfix helps us distuinguish between 1 and 0 lines.
	lines=$(($(echo "$result" | wc -l) - 1))

	# Update position.
	setvar ${this}position $(($position + $lines))

	# Remove postfix.
	if [ $lines -gt 0 ]; then
		result="${result%${IFS}EOF}"
	else
		result=
	fi

	# Return the resulting line.
	$caller.setvar "$1" "$result"
	$caller.setvar "$2" "$lines"
}



#
# A raw sender class, .
#
bsda:obj:createClass bsda:messaging:FileSystemSender \
	implements:bsda:messaging:Sender \
	r:private:lock \
		"A Lock instance." \
	r:private:queue \
		"The queue file." \
	i:private:init \
		"The constructor." \
	c:private:clean \
		"The destructor." \

#
# The constructor checks whether the message queue is available.
#
# @param 1
#	The file name of the message queue.
# @return
#	0 if everything goes fine
#	1 if creating a locking object fails
#
bsda:messaging:FileSystemSender.init() {
	lockf -ks "$1" chmod 0600 "$1" || return 1
	bsda:messaging:Lock ${this}lock "$1.lock" || return 1
	setvar ${this}queue "$1"
}

#
# Borrow the destructor from the listener.
#
bsda:messaging:FileSystemSender.clean() {
	bsda:messaging:FileSystemListener.clean "$@"
}

#
# Sends a message.
#
# @param 1
#	The message to send.
#
bsda:messaging:FileSystemSender.send() {
	local queue result lock

	$this.getLock lock
	$this.getQueue queue

	# Forbid reading.
	$lock.lockRead

	# Write the data.
	echo "$1" >> "$queue"

	# Permit reading.
	$lock.unlockRead
}


#
# A synchronus, file system based message queue access class. This can be used
# for many to many communication. It is still safe to use this after a fork.
# However the messenger object should not be synchronized between forked
# processes to preserve internal states.
#
# Because it is a synchronous message queue, receive() will always return
# all queued up message lines and send() will only work if there is no
# unread data left in the queue.
#
bsda:obj:createClass bsda:messaging:FileSystemMessenger \
	implements:bsda:messaging:Messenger \
	extends:bsda:messaging:FileSystemListener \


#
# Sends a message, unless there are unread messages in the queue.
#
# This means it might fail, in that case receive() has to be called before
# send() has a chance to work. There is no command that does send and
# receive at once, because it might be important that all receive data
# is processed in order to create a correct message.
#
# @param 1
#	The message to send.
# @return
#	0 if the message was sent
#	1 if the queue contains unreceived messages.
#
bsda:messaging:FileSystemMessenger.send() {
	local position queue result lock

	$this.getLock lock
	$this.getPosition position
	$this.getQueue queue

	# Forbid reading.
	$lock.lockRead

	# Check whether this process is up to date. I.e. there are no unread
	# messages in the queue.
	if [ $(($(wc -l < "$queue") - $position)) -eq 0 ]; then
		# This process is up to date. Write the data.
		echo "$1" >> "$queue"

		# Permit reading.
		$lock.unlockRead

		# Update the queue position, no need to read our own message.
		setvar ${this}position $(($position + $(echo "$1" | wc -l)))
		return 0
	else
		# Sending has failed, because we are not in sync with the
		# queue.

		# Permit reading.
		$lock.unlockRead
		return 1
	fi
	
}

