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
# version 0.9999

# Include once.
test -n "$bsda_pkg" && return 0
bsda_pkg=1

# Include framework for object oriented shell scripting.
. "${bsda_dir:-.}/bsda_obj.sh"

# Import the bsda:download library.
. "${bsda_dir:-.}/bsda_download.sh"

#
# Offers classes for package handling.
#

# Package exceptions.
readonly bsda_pkg_ERR_PACKAGE_CONTENTS_FORMAT=1
readonly bsda_pkg_ERR_PACKAGE_ORIGIN_UNMATCHED=2
readonly bsda_pkg_ERR_PACKAGE_ORIGIN_UNINDEXED=3
readonly bsda_pkg_ERR_PACKAGE_NAME_UNMATCHED=4
readonly bsda_pkg_ERR_PACKAGE_NAME_UNINDEXED=5
readonly bsda_pkg_ERR_PACKAGE_NAME_AMBIGUOUS=6
readonly bsda_pkg_ERR_PACKAGE_NEW_ORIGIN_AMBIGUOUS=7
readonly bsda_pkg_ERR_PACKAGE_NEW_NAME_AMBIGUOUS=8
readonly bsda_pkg_ERR_PACKAGE_OLD_ORIGIN_AMBIGUOUS=9
readonly bsda_pkg_ERR_PACKAGE_OLD_NAME_AMBIGUOUS=10
readonly bsda_pkg_ERR_PACKAGE_OLD_ORIGIN_UNMATCHED=11
readonly bsda_pkg_ERR_PACKAGE_OLD_NAME_UNMATCHED=12
readonly bsda_pkg_ERR_PACKAGE_OLD_CONFLICT=13

# Index exceptions.
readonly bsda_pkg_ERR_INDEX_FILE_MISSING=14
readonly bsda_pkg_ERR_INDEX_MOVED_MISSING=15

# Moved exceptions.
readonly bsda_pkg_ERR_MOVED_FILE_MISSING=16

# File exceptions.
readonly bsda_pkg_ERR_DOWNLOADER_INVALID=17
readonly bsda_pkg_ERR_FILE_DIR_PERM=18
readonly bsda_pkg_ERR_BACKUP_DIR_PERM=19
readonly bsda_pkg_ERR_FILE_MISSING=20
readonly bsda_pkg_ERR_FILE_INVALID=21

# INDEX columns.
readonly bsda_pkg_IDX_PKG=1
readonly bsda_pkg_IDX_ORIGIN=2
readonly bsda_pkg_IDX_PREFIX=3
readonly bsda_pkg_IDX_COMMENT=4
readonly bsda_pkg_IDX_DESCRIPTION=5
readonly bsda_pkg_IDX_MAINTAINER=6
readonly bsda_pkg_IDX_CATEGORIES=7
readonly bsda_pkg_IDX_DIRECTDEPENDS=8
readonly bsda_pkg_IDX_DEPENDS=9
readonly bsda_pkg_IDX_WWW=10
readonly bsda_pkg_IDX_PERLVERSION=11
readonly bsda_pkg_IDX_PERLMODULES=12

# MOVED columns.
readonly bsda_pkg_MOV_OLDORIGIN=1
readonly bsda_pkg_MOV_NEWORIGIN=2
readonly bsda_pkg_MOV_DATE=3
readonly bsda_pkg_MOV_REASON=4

#
# An error storage variable.
# If an error occurs this should be set back to 0 wherever the error is
# dealt with.
#
bsda_pkg_errno=0

#
# The following is a list of all implemented classes:
#	bsda:pkg:Index		INDEX file access
#	bsda:pkg:File		Package file access
#	bsda:pkg:Package	Package access
#	bsda:pkg:Moved		MOVED file access
#



#
# An instance of this class represents and index file. It is the main
# source of information about packages.
#
# By calling identifyPackages with a package file, the file can be built
# into the index representation. This way indexed and unindexed packages can
# be handled through a single interface.
#
bsda:obj:createClass bsda:pkg:Index \
	r:private:index	\
		"INDEX filename." \
	r:private:moved \
		"A Moved instance." \
	w:private:fileDir \
	x:protected:getFileDir \
		"The package directory." \
	w:private:fileSuffix \
	x:protected:getFileSuffix \
		"The expected package file name suffix." \
	w:private:backupDir \
	x:protected:getBackupDir \
		"The directory to store backups in." \
	w:private:backupSuffix \
	x:protected:getBackupSuffix \
		"The backup file name suffix." \
	w:private:downloader \
	x:protected:getDownloader \
		"A bsda:download:Manager instance." \
	w:private:downloads \
		"A list of the active downloads." \
	w:private:downloadsCompleted \
		"A list of instantly completed downloads." \
	r:private:originPrefix \
		"The ports directory used for building the packages." \
	r:private:packages \
		"The packages already read from the index." \
	r:private:mappedPackages \
		"The same list of packages only mapped by package origin" \
		"in the format: |<origin>|<Package>" \
	r:private:mappedNames \
		"An incomplete list of packages in the format:" \
		"	|<name>|<Package>" \
	r:private:originBlacklist \
		"A list of unavailable encountered origins." \
	i:private:init \
		"Constructor." \
	x:private:search \
		"Returns index lines matching a given string and column." \
	x:public:identifyPackages \
		"Returns a list of packages by a given glob pattern." \
	x:public:substitutePackage \
		"Takes two package identifiers and returns a package for the" \
		"first one, setting everything up to replace the second one." \
	x:private:identifyOrigins \
		"Returns a list of packages from an origin glob pattern." \
	x:private:identifyNames \
		"Returns a list of packages from a package name glob pattern." \
	x:public:getPackagesByOrigins \
		"Takes a list of origins and returns a list of Packages." \
	x:public:getPackagesByNames \
		"Takes a list of package names and returns" \
		"a list of Packages." \
	x:private:addPackages \
		"Adds packages to the packages list." \
	x:private:getKnownPackages \
		"Gets already known packages by origin." \
	x:public:registerDownloader \
		"Registers a download manager that packages can use for" \
		"fetching." \
	x:protected:downloadStarted \
		"Called by a Package to notify about a started download." \
	x:public:completedDownloads \
		"Returns a list of newly downloaded packages." \

#
# The constructor for an index interface object.
#
# @param 1
#	The INDEX file name.
# @param 2
#	The Moved instances.
# @param 3
#	The optional package file directory, defaults to ".".
# @param 4
#	The optional package file suffix, defaults to ".tbz".
# @param 5
#	The optional backup directory, defaults to ".".
# @param 6
#	The optional package backup file suffix, defaults to ".tbz".
# @throws bsda_pkg_ERR_INDEX_FILE_MISSING
#	Is thrown if parameter one is not a file.
# @throws bsda_pkg_ERR_INDEX_MOVED_MISSING
#	Is thrown if the second parameter is not a bsda:pkg:Moved object.
# @throws bsda_pkg_ERR_BACKUP_DIR_PERM
#	No write access to the backup directory.
#
bsda:pkg:Index.init() {
	local origin backup dir
	# Check the INDEX file.
	if [ ! -f "$1" ]; then
		bsda_pkg_errno=$bsda_pkg_ERR_INDEX_FILE_MISSING
		return 1
	fi
	setvar ${this}index "$1"
	origin="$(head -n1 "$1"| cut -d\| -f$bsda_pkg_IDX_ORIGIN)"
	setvar ${this}originPrefix "${origin%/*/*}/"

	# Check the MOVED file.
	if ! bsda:pkg:Moved.isInstance "$2"; then
		bsda_pkg_errno=$bsda_pkg_ERR_INDEX_MOVED_MISSING
		return 1
	fi
	setvar ${this}moved $2

	# Determine the package file directory.
	if [ -z "$3" ]; then
		dir="."
	else
		dir="${3%/}"
	fi
	$this.setFileDir "$dir"

	$this.setFileSuffix "${4:-.tbz}"

	# Determine backup directory.
	if [ -z "$5" ]; then
		backup="."
	else
		backup="${5%/}"
	fi
	$this.setBackupDir "$dir"

	# Check backup directory permissions.
	if (/bin/mkdir -p "$backup/" && /usr/bin/touch "$backup/.$bsda_obj_pid") 2> /dev/null; then
		/bin/rm "$backup/.$bsda_obj_pid"
	else
		bsda_pkg_errno=$bsda_pkg_ERR_BACKUP_DIR_PERM
		return 1
	fi

	$this.setBackupSuffix "${6:-.tbz}"
}

#
# This returns lines from the index where a column exactly matches the
# given strings.
#
# @param 1
#	The name of the variable to return results to.
# @param 2
#	The column to match against.
# @param 3
#	The line break delimited search strings.
# @param 4
#	The optional column to output. If this is omitted the whole line
#	is returned.
#
bsda:pkg:Index.search() {
	local index lines length

	$this.getIndex index
	# The number of lines to search for.
	length=$(echo "$3" | /usr/bin/wc -l)

	# Get the matching index lines.
	lines="$(/usr/bin/awk -F\| "
		BEGIN {
			# Initialize result counter.
			count = 0
			# Create an array with the search strings as indices.
			$(echo "$3" | sed -e 's/^/search["/1' -e 's/$/"]/1')
		}

		# Check whether the current line matches an array element.
		\$$2 in search {
			# Print the requested line.
			print \$${4:-0}
			# Exit if all requested lines have been found.
			if (++count == $length)
				exit 0
		}
	" "$index")"

	# Return the matching index lines.
	$caller.setvar "$1" "$lines"
	return 0
}

#
# Takes a glob pattern and returns a list of matching Packages.
#
# @param 1
#	The variable to store the result in.
# @param 2
#	The glob pattern to match.
# @throws bsda_pkg_ERR_PACKAGE_CONTENTS_FORMAT
#	Forwarded from File.getContents().
# @throws bsda_pkg_ERR_PACKAGE_ORIGIN_UNMATCHED
#	Forwarded from identifyOrigins().
# @throws bsda_pkg_ERR_PACKAGE_ORIGIN_UNINDEXED
#	Forwarded from identifyOrigins().
# @throws bsda_pkg_ERR_PACKAGE_NAME_UNMATCHED
#	Forwarded from identifyNames().
# @throws bsda_pkg_ERR_PACKAGE_NAME_AMBIGUOUS
#	Forwarded from identifyNames().
# @throws bsda_pkg_ERR_PACKAGE_NAME_UNINDEXED
#	Forwarded from identifyNames().
#
bsda:pkg:Index.identifyPackages() {
	local IFS

	IFS='
'

	#
	# The first case is that the package is a file and hence does not
	# have to undergo any matching.
	#
	if [ -f "$2" ]; then
		local file name orgin null pkg origins

		# Create File instance and read contents.
		bsda:pkg:File file "$2"
		if ! $file.getContents name origin null null null; then
			# Foreward errors.
			return 1
		fi

		# Check whether a package with the given origin already
		# exists.
		$this.getKnownPackages pkg null "$origin"
		if [ -z "$pkg" ]; then
			# No matching package exists. Create one.
			bsda:pkg:Package pkg $this "$origin" "$name" $file
			# Remember the package.
			$this.addPackages $pkg
			# Remove the origin from the blacklist.
			setvar ${this}originBlacklist "$($this.getOriginBlacklist | grep -vFx "$origin")"
		else
			# Repopulate the package with the new data.
			$pkg.init "$origin" "$name" $file
		fi

		# Return it.
		$caller.setvar "$1" $pkg
		return 0
	fi

	#
	# This is a regular package glob pattern.
	#
	local packages
	case "$2" in
		*/*)
			# This is an origin pattern.
			if ! $this.identifyOrigins packages "$2"; then
				# Foreward errors.
				return 1
			fi
			# Return the matching packages.
			$caller.setvar "$1" "$packages"
			return 0
		;;
		*)
			# This is a package name or LATEST_LINK pattern.
			if ! $this.identifyNames packages "$2"; then
				# Foreward errors.
				return 1
			fi
			# Return the matching packages.
			$caller.setvar "$1" "$packages"
			return 0
		;;
	esac
}

#
# Returns a new package in such a way that it will substitute an old package
# upon install.
#
# For this to work it is important that the old package is not already present
# and thus all substitutePackage() calls should occur before the first call
# of identifyPackages().
#
# For the new packag the same matching rules apply as for everything
# returned by identifyPackages. An additional limitation is that the new
# package needs to be unambiguous, i.e. whatever was specified should match
# a single package.
#
# The old package is more limited, it should unambiguously match an installed
# package. Glob patterns are permitted as long as they only match a single
# installed package.
#
# @param &1
#	The name of the variable to return the new package to.
# @param 2
#	The new package.
# @param 3
#	An identifier for an already existing package.
# @throws bsda_pkg_ERR_PACKAGE_CONTENTS_FORMAT
#	Forwarded from identifyPackages(), always because of the new package.
# @throws bsda_pkg_ERR_PACKAGE_ORIGIN_UNMATCHED
#	Forwarded from identifyPackages(), always because of the new package.
# @throws bsda_pkg_ERR_PACKAGE_ORIGIN_UNINDEXED
#	Forwarded from identifyPackages(), always because of the new package.
# @throws bsda_pkg_ERR_PACKAGE_NAME_UNMATCHED
#	Forwarded from identifyPackages(), always because of the new package.
# @throws bsda_pkg_ERR_PACKAGE_NAME_AMBIGUOUS
#	Forwarded from identifyPackages(), always because of the new package.
# @throws bsda_pkg_ERR_PACKAGE_NAME_UNINDEXED
#	Forwarded from identifyPackages(), always because of the new package.
# @throws bsda_pkg_ERR_PACKAGE_NEW_ORIGIN_AMBIGUOUS
#	Thrown if the new package was given as an ambiguous origin glob.
# @throws bsda_pkg_ERR_PACKAGE_NEW_NAME_AMBIGUOUS
#	Thrown if the new package was given as an ambiguous package name glob.
# @throws bsda_pkg_ERR_PACKAGE_OLD_ORIGIN_AMBIGUOUS
#	Thrown if the old package was given as an ambiguous origin glob.
# @throws bsda_pkg_ERR_PACKAGE_OLD_ORIGIN_UNMATCHED
#	Thrown if the old package was given as an origin not matching any
#	installed package.
# @throws bsda_pkg_ERR_PACKAGE_OLD_NAME_UNMATCHED
#	Thrown if the old package was given as a package name not matching
#	any installed package.
# @throws bsda_pkg_ERR_PACKAGE_OLD_NAME_AMBIGUOUS
#	Thrown if the old package was given as an ambiguous name. This can
#	happen if old package was defined as a name glob or in LATEST_LINK
#	style matching more than one installed package.
# @throws bsda_pkg_ERR_PACKAGE_OLD_CONFLICT
#	This is thrown if the old package was previously returned from the
#	index and thus a Package instance resembling it already exists.
#	This is not accepted, because it can lead to conflicts when packages
#	are installed.
#
bsda:pkg:Index.substitutePackage() {
	local IFS newPkg origin known missing mappedPackages mappedNames name

	IFS='
'

	#
	# Try to get the new package.
	#
	if ! $this.identifyPackages newPkg "$2"; then
		# Forward errors.
		$caller.setvar "$1"
		return 1
	fi

	# There must be a single package identified.
	if [ $(echo "$newPkg" | /usr/bin/wc -l) -gt 1 ]; then
		case "$2" in
		*/*)
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_NEW_ORIGIN_AMBIGUOUS
		;;
		*)
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_NEW_NAME_AMBIGUOUS
		;;
		esac
		$caller.setvar "$1"
		return 1
	fi

	#
	# Try to get the old package origin.
	#
	name=
	origin=
	case "$3" in
	*/*)
		name="$(/usr/sbin/pkg_info -qO "$3" 2> /dev/null)"
		# Check for ambiguous matches.
		if [ $(echo "$name" | /usr/bin/wc -l) -gt 1 ]; then
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_OLD_ORIGIN_AMBIGUOUS
			$caller.setvar "$1"
			return 1
		fi
		# Check for not matching origins.
		if [ -z "$name" ]; then
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_OLD_ORIGIN_UNMATCHED
			$caller.setvar "$1"
			return 1
		fi
		origin="$(/usr/sbin/pkg_info -qo $name)"
	;;
	*)
		origin="$(/usr/sbin/pkg_info -qo "$3" 2> /dev/null)"
		# Check whether there were any matches.
		if [ -z "$origin" ]; then
			# No matches were there, try to find something
			# assuming LATEST_LINK style name.
			origin="$(/usr/sbin/pkg_info -qo "$3-*" 2> /dev/null)"
			if [ -z "$origin" ]; then
				bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_OLD_NAME_UNMATCHED
				$caller.setvar "$1"
				return 1
			fi
		fi
		# Check for ambiguous matches.
		if [ $(echo "$origin" | /usr/bin/wc -l) -gt 1 ]; then
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_OLD_NAME_AMBIGUOUS
			$caller.setvar "$1"
			return 1
		fi
		name="$(/usr/sbin/pkg_info -qO "$origin")"
	;;
	esac

	#
	# The old package must be unknown as of now, or there might be
	# conflicts when installing packages.
	#
	$this.getKnownPackages known missing "$origin"
	if [ -n "$known" ]; then
		# The old package is already known, bail out now.
		bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_OLD_CONFLICT
		$caller.setvar "$1"
		return 1
	fi

	#
	# Wrap the new package up.
	#
	
	# Set up package mapping.
	$this.getMappedPackages mappedPackages
	setvar ${this}mappedPackages "${mappedPackages:+$mappedPackages$IFS}|$origin|$newPkg"
	$this.getMappedNames mappedNames
	setvar ${this}mappedNames "${mappedNames:+$mappedNames$IFS}|$name|$newPkg"

	# Tell the package it is replacing another one.
	$newPkg.addMoved "$origin"

	# Return the new package.
	$caller.setvar "$1" $newPkg
	return 0
}

#
# Takes an origin glob pattern and returns a list of Packages matching these.
#
# The Packages are already installed and have to be listed in the index
# to appear, unless they have previously been supplied directly through
# a package file.
#
# Exactly matching origins are returned even when not installed.
#
# @param 1
#	The name of the variable to store the list of matching packages in.
# @param 2
#	The origin glob pattern to match.
# @throws bsda_pkg_ERR_PACKAGE_ORIGIN_UNMATCHED
#	Thrown when a glob pattern yields no installed packages or all matching
#	installed packages are unindexed.
# @throws bsda_pkg_ERR_PACKAGE_ORIGIN_UNINDEXED
#	Thrown when an origin is not indexed.
#
bsda:pkg:Index.identifyOrigins() {
	local IFS matching
	IFS='
'

	matching=

	# Redirect requests that are not glob patterns.
	if ! echo "$2" | egrep -q '\*|\?|\[.*]'; then
		$this.getPackagesByOrigins matching "$2"
		# Check whether there was a match.
		if [ -z "$matching" ]; then
			# This origin is not indexed.
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_ORIGIN_UNINDEXED
			return 1
		fi
		# Return the matches.
		$caller.setvar "$1" "$matching"
		return 0
	fi

	# The pattern really is a glob pattern. Get installed packages matching
	# this.
	$this.getPackagesByOrigins matching "$(pkg_info -qo $(pkg_info -qO "$2"))"
	# Check whether there was a match.
	if [ -z "$matching" ]; then
		# The origin glob pattern did not yield any indexed matches.
		bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_ORIGIN_UNMATCHED
		return 1
	fi
	$caller.setvar "$1" "$matching"

	return 0
}

#
# Returns a list of matching Packages for a package name glob pattern or a
# single Package for a specific or LATEST_LINK style package name.
#
# Specific package names are those matching an installed or indexed package,
# LATEST_LINK style names are subject to a lot of guesswork.
#
# @param 1
#	The name of the variable to store the list of matching packages in.
# @param 2
#	The origin glob pattern to match.
# @throws bsda_pkg_ERR_PACKAGE_NAME_UNMATCHED
#	Thrown when a glob pattern returns no installed packages from the
#	index.
# @throws bsda_pkg_ERR_PACKAGE_NAME_AMBIGUOUS
#	Thrown when a package name could not be ambigously identified.
# @throws bsda_pkg_ERR_PACKAGE_NAME_UNINDEXED
#	Thrown when a package name could not be found in the index.
#
bsda:pkg:Index.identifyNames() {
	local IFS matching
	IFS='
'

	# Deal with glob patterns.
	if echo "$2" | egrep -q '\*|\?|\[.*]'; then
		$this.getPackagesByOrigins matching "$(pkg_info -qo "$2" 2> /dev/null)"
		# Check for matches.
		if [ -z "$matching" ]; then
			# Either there are no installed packages matching or
			# none of them are indexed.
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_NAME_UNMATCHED
			return 1
		fi
		# Return the matching Packages.
		$caller.setvar "$1" "$matching"
		return 0
	fi

	# Package names that are not glob patterns are really difficult.
	# They can be the complete name of an installed package, a
	# complete name of indexed package, the package name without a version
	# suffix or a LATEST_LINK name.
	# LATEST_LINK however is not known, so there is going to be a lot
	# of guesswork.

	# First try whether the name matches an installed package.
	$this.getPackagesByOrigins matching "$(pkg_info -qo "$2" 2> /dev/null)"

	# If no match has been found and indexed try to get a match
	# from the INDEX.
	if [ -z "$matching" ]; then
		$this.getPackagesByNames matching "$2"
	fi

	# This is a bailout point.
	if [ -n "$matching" ]; then
		# A safe match has either been found from the
		# index or the installed packages.
		$caller.setvar "$1" "$matching"
		return 0
	fi

	# From this point it is assumed that the package name is a LATEST_LINK.
	# This is often the ports origin without the category, however we also
	# want to find other cases like ru-apache (russian/apache13).
	local index pattern numbers lines prefix origin

	$this.getOriginPrefix prefix
	$this.getIndex index

	# Create a grep pattern. Here are some examples:
	#	ru-apache13 -> ru-apache-[^-]*
	#	firefox35 -> firefox-[^-]*
	pattern="$(echo "$2" | sed 's/[0-9]*$/-[^-]*/1')"
	# Get the line numbers of package names matching this pattern.
	numbers="$(cut -d\| -f$bsda_pkg_IDX_PKG "$index" | grep -nx "$pattern" | sed 's/:.*/p/1' | rs -C\;)"
	# Get the lines from the index.
	lines="$(sed -n "${numbers%;}" "$index")"

	# Check whether more than one package have been matched (e.g. that'd be
	# the case for firefox35).
	if [ $(echo "$lines" | wc -l) -gt 1 ]; then
		# Too many package names have been matched, so we match the
		# package name against the origins of the found packages.
		numbers="$(echo "$lines" | cut -d\| -f$bsda_pkg_IDX_ORIGIN | sed 's|.*/||1' | grep -nFx "$2" | sed 's/:.*/p/1' | rs -C\;)"
		lines="$(echo "$lines" | sed -n "${numbers%;}")"

		# Check whether there is still more than one match.
		if [ $(echo "$lines" | wc -l) -gt 1 ]; then
			# If there is more than one origin around we prefer
			# the one that is alread installed.
			numbers="$(echo "$lines" | cut -d\| -f$bsda_pkg_IDX_ORIGIN | sed "s|$prefix||1" | grep -nFx "$(pkg_info -qoa)" | sed 's/:.*/p/1' | rs -C\;)"
			lines="$(echo "$lines" | sed -n "${numbers%;}")"
		fi

		# Bail out if there is still more than one match.
		if [ $(echo "$lines" | wc -l) -gt 1 ]; then
			bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_NAME_AMBIGUOUS
			return 1
		fi
	fi

	# Bail out if no package matching the requested could be found in the
	# index.
	if [ -z "$lines" ]; then
		bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_NAME_UNINDEXED
		return 1
	fi

	# Arriving here means that the LATEST_LINK guessing has actually
	# provided us with a single package.
	origin="$(echo "$lines" | cut -d\| -f$bsda_pkg_IDX_ORIGIN)"
	# Because we have our information from the index we can skip the
	# sanity checks here.
	$this.getPackagesByOrigins matching "${origin#$prefix}"
	# Return the matching package.
	$caller.setvar "$1" "$matching"
}

#
# Takes a list of origins and returns a list of Package instances. If the
# Package is not known, it is created from the index.
#
# @param 1
#	The name of the variable to return the list of Packages in.
# @param 2
#	A list of origins.
# @param 3
#	If set the moved file will not be checked for missing packages.
#	This also prevents the blacklist from being updated.
#
bsda:pkg:Index.getPackagesByOrigins() {
	local IFS packages origins origin pkg prefix name newPackages
	local lines line blacklist missing

	IFS='
'

	# Get the ports origin prefix.
	$this.getOriginPrefix prefix
	# Get the origin blacklist.
	$this.getOriginBlacklist blacklist

	# The list of Package instances to return.
	packages=
	# The list of newly created Package instances.
	newPackages=

	# Collect the encountered origins.
	origins=
	# Apply the blacklist to the requested origins.
	missing="$(echo "$2" | grep -vFx "$blacklist")"

	$this.getKnownPackages packages missing "$missing"

	# If all requested origins have been found, return.
	if [ -z "$missing" ]; then
		# Return the list of packages.
		$caller.setvar "$1" "$packages"
		return 0
	fi

	#
	# Try to create new Package instances for the remaining origins.
	#

	$this.search lines $bsda_pkg_IDX_ORIGIN "$(echo "$missing" | sed "s|^|$prefix|1")"
	# Collect available origins.
	origins=
	# Create packages.
	for line in $lines; do
		# Create a new Package instance.
		name="$(echo "$line" | cut -d\| -f$bsda_pkg_IDX_PKG,$bsda_pkg_IDX_ORIGIN)"
		origin="${name##*|$prefix}"
		name="${name%|*}"
		bsda:pkg:Package pkg $this "$origin" "$name" "$line"
		packages="$packages${packages:+$IFS}$pkg"

		# Store the Package in the list of all Packages.
		newPackages="$newPackages${newPackages:+$IFS}$pkg"

		# Collect available origins.
		origins="$origins${origins:+$IFS}$origin"
	done

	# Store the newly created packages in the list of all packages.
	$this.addPackages "$newPackages"

	# Remove available origins from the list of missing origins.
	missing="$(echo "$missing" | grep -vFx "$origins")"

	# If all requested origins have been found, return.
	if [ -z "$missing" -o -n "$3" ]; then
		# Return the list of packages.
		$caller.setvar "$1" "$packages"
		return 0
	fi


	#
	# Check the MOVED file for still missing packages.
	#
	local moved oldorigin oldname neworigin

	# Get the Moved instances.
	$this.getMoved moved

	$moved.search lines $bsda_pkg_MOV_OLDORIGIN "$missing"
	# Collect the available origins to remove from the
	# list of missing packages.
	origins=
	# Try to get the packages. This cannot be done in a
	# single chunk, which would benefit performance, because
	# the original origin would be lost. This would break
	# blacklisting.
	for line in $lines; do
		oldorigin="$(echo "$line" | cut -d\| -f$bsda_pkg_MOV_OLDORIGIN,$bsda_pkg_MOV_NEWORIGIN)"
		neworigin="${oldorigin##*|}"
		oldorigin="${oldorigin%|*}"

		# Continue with the next line if there is no
		# replacement package.
		test -z "$neworigin" && continue

		# Try to get the package.
		$this.getPackagesByOrigins pkg "$neworigin" 1

		# If the new origin does not work out, remember
		# it for blacklisting and go on with the next
		# line.
		if [ -z "$pkg" ]; then
			missing="$missing${missing:+$IFS}$neworigin"
			continue
		fi

		# Tell the package that it was MOVED.
		$pkg.addMoved "$oldorigin"

		# There actually is a package, remember it.
		packages="$packages${packages:+$IFS}$pkg"
		# Create an alias with the old origin.
		eval "${this}mappedPackages=\"\$${this}mappedPackages\${${this}mappedPackages:+\$IFS}|$oldorigin|$pkg\""
		# Maybe pkg_info can tell us about a names.
		oldname="$(/usr/sbin/pkg_info -qO "$oldorigin")"
		test -n "$oldname" && eval "${this}mappedNames=\"\$${this}mappedNames\${${this}mappedNames:+\$IFS}|$oldname|$pkg\""
		# Remember the old origin to remove it from
		# the list of missing packages.
		origins="$origins${origins:+$IFS}$oldorigin"
	done
	

	# Remove available origins from the list of missing origins.
	missing="$(echo "$missing" | grep -vFx "$origins")"

	# Store the blacklist.
	setvar ${this}originBlacklist "$blacklist${blacklist:+${missing:+$IFS}}$missing"

	# Return the list of packages.
	$caller.setvar "$1" "$packages"
}

#
# Returns a list of Packages for a list of package names.
#
# This solely works with packages listed in the INDEX.
#
# @param 1
#	The name of the variable to return the list of Packages to.
# @param 2
#	The list of package names.
#
bsda:pkg:Index.getPackagesByNames() {
	local IFS index prefix numbers origins packages pkg bufferedPackages names
	IFS='
'

	#
	# First get cached package names.
	#

	# A list of packages found.
	bufferedPackages=
	# The names of packages found.
	names=
	for pkg in $($this.getMappedNames | /usr/bin/grep -F "$(echo "$2" | /usr/bin/sed -e 's/^/|/1' -e 's/$/|/1')"); do
		pkg="${pkg#|}"
		bufferedPackages="${bufferedPackages:+$bufferedPackages$IFS}${pkg#*|}"
		names="${names:+$names$IFS}${pkg%%|*}"
	done
	# Assemble a list of names yet to be searched.
	names="$(echo "$2" | /usr/bin/grep -vxF "$names")"

	# If nothing is left to be done, skip the rest.
	if [ -z "$names" ]; then
		$caller.setvar "$1" "$bufferedPackages"
		return
	fi

	#
	# Properly request the remaining package names by origin.
	#
	$this.getOriginPrefix prefix
	$this.getIndex index

	# Get the origins from the index.
	$this.search origins $bsda_pkg_IDX_PKG "$names" $bsda_pkg_IDX_ORIGIN
	origins="$(echo "$origins" | sed "s|$prefix||1")"

	# Forward the list of of origins to the getPackagesByOrigins() method.
	$this.getPackagesByOrigins packages "$origins"
	# Return the Package instances.
	$caller.setvar "$1" "$bufferedPackages${bufferedPackages:+${packages:+$IFS}}$packages"
}

#
# Adds packages to the list of packages. This is intended for private use only.
#
# @param 1
#	The packaes to add to the list of packages.
#
bsda:pkg:Index.addPackages() {
	local IFS pkg
	IFS='
'

	eval "${this}packages=\"\$${this}packages\${${this}packages:+\$IFS}$1\""
	for pkg in $1; do
		eval "${this}mappedPackages=\"\$${this}mappedPackages\${${this}mappedPackages:+\$IFS}|$($pkg.getOrigin)|$pkg\""
		eval "${this}mappedNames=\"\$${this}mappedNames\${${this}mappedNames:+\$IFS}|$($pkg.getName)|$pkg\""
	done
}

#
# Returns a list of already known packages for a list of origins.
#
# @param 1
#	The name of the variable to store the list of matching packages in.
# @param 2
#	The name of the variable the unmatched origins are stored in.
# @param 3
#	A list of origins.
#
bsda:pkg:Index.getKnownPackages() {
	local IFS pkg origins origin packages

	IFS='
'

	# The list of packages.
	packages=
	# The list of matched origins.
	origins=

	# Fetch all available origins from the list of already existing
	# packages.
	for pkg in $($this.getMappedPackages | /usr/bin/grep -F "$(echo "$3" | /usr/bin/sed -e 's/^/|/1' -e 's/$/|/1')"); do
		# Fetch origin and Package instance from the mappedPackage line.
		origin="${pkg%|*}"
		origin="${origin#|}"
		pkg="${pkg##*|}"

		# Store the match.
		packages="$packages${packages:+$IFS}$pkg"

		# Add the current origin to the list of encountered origins.
		origins="$origins${origins:+$IFS}$origin"
	done

	# Return the matched packages.
	$caller.setvar "$1" "$packages"

	# Return a list of missing origins.
	$caller.setvar "$2" "$(echo "$3" | grep -vFx "$origins")"
}

#
# Registers a download manager that packages can use for fetching.
#
# If the given downloader is valid the package file directory will be checked
# for write permissions.
#
# @param 1
#	A bsda:download:Manager instance.
# @throws bsda_pkg_ERR_DOWNLOADER_INVALID
#	Parameter 1 was not a bsda:download:Manager instance.
# @throws bsda_pkg_ERR_FILE_DIR_PERM
#	No write access to the package file directory.
#
bsda:pkg:Index.registerDownloader() {
	local dir

	# Check download manager.
	if ! bsda:download:Manager.isInstance "$1"; then
		bsda_pkg_errno=$bsda_pkg_ERR_DOWNLOADER_INVALID
		return 1
	fi

	# Check package file directory permissions.
	$this.getFileDir dir
	if (/bin/mkdir -p "$dir/" && /usr/bin/touch "$dir/.$bsda_obj_pid") 2> /dev/null; then
		/bin/rm "$dir/.$bsda_obj_pid"
	else
		bsda_pkg_errno=$bsda_pkg_ERR_DOWNLOADER_DIR_PERM
		return 1
	fi


	$this.setDownloader $1
	return 0
}

#
# Records download jobs that got started.
#
# @param 1
#	The optional running download job.
#
bsda:pkg:Index.downloadStarted() {
	local IFS downloader downloads pkg

	IFS='
'

	# Get the caller.
	$caller.getObject pkg

	# Check if the download has a job.
	if [ -n "$1" ]; then
		# Append the job to the list of running downloads.
		$this.getDownloads downloads
		$this.setDownloads "${downloads:+$downloads$IFS}$1|$pkg"
	else
		# Just list the package as a completed download.
		$this.getDownloadsCompleted downloads
		$this.setDownloadsCompleted "${downloads:+$downloads$IFS}$pkg"
	fi
}

#
# Returns a list of Package instances that finished downloading.
#
# Every download will only be returned once.
#
# @param &1
#	The name of the variable to return the list to.
# @return 0
#	New completed downloads are returned.
# @return 1
#	There are no downloads to return.
#
bsda:pkg:Index.completedDownloads() {
	local IFS downloader jobs job downloads completed

	IFS='
'

	# Get the downloads that were instantly completed.
	$this.getDownloadsCompleted completed
	$this.setDownloadsCompleted

	# Check if the downloader is active.
	$this.getDownloader downloader
	if [ -n "$downloader" ]; then
		# There is a downloader, so it is necessary to ask it for
		# updates.

		# Synchronize with the background downloader.
		$downloader.run

		# Ask for completed jobs.
		if $downloader.completedJobs jobs; then
			# The download results are not really interesting,
			# throw the jobs away.
			for job in $jobs; do
				$job.delete
			done

			# Assemble a list of completed jobs.
			$this.getDownloads downloads
			completed="${completed:+$completed$IFS}$(echo "$downloads" | /usr/bin/grep -F "$jobs" | /usr/bin/sed 's/.*|//')"
			downloads="$(echo "$downloads" | /usr/bin/grep -vF "$jobs")"
			$this.setDownloads "$downloads"
		fi
	fi

	# Return the list of completed jobs.
	$caller.setvar "$1" "$completed"
	# Generate the correct return value.
	test -n "$completed"
}

#
# An instance of this class represents a package file.
#
bsda:obj:createClass bsda:pkg:File \
	r:public:file \
		"The fully qualified file name." \
	i:private:init \
		"Constructor." \
	x:public:getContents \
		"Returns the data from the +CONTENTS file in a package." \

#
# The constructor initializes attributes.
#
# @param 1
#	The fully qualified file name of the file this object represents.
#
bsda:pkg:File.init() {
	setvar "${this}file" "$1"
}

#
# Returns the data in the +CONTENTS file of a package file.
#
# @param &1
#	The name of the variable the name should be stored in.
# @param &2
#	The name of the variable the origin should be stored in.
# @param &3
#	The name of the variable the dependencies, as a list of origins,
#	should be stored in.
# @param &4
#	The variable dependency names should be stored in.
# @param &5
#	The name of the variable the conflict patters should be stored in.
# @throws bsda_pkg_ERR_PACKAGE_CONTENTS_FORMAT
#	This error is set if the package format version is not 1.1.
#
bsda:pkg:File.getContents() {
	local IFS file line format name orgin dependencies depNames conflicts

	IFS='
'

	$this.getFile file

	name=
	origin=
	dependencies=
	depNames=
	conflicts=

	# Process the +CONTENTS file in the tar archive line by line.
	for line in $(tar -xqOf "$file" '+CONTENTS'); do
		case "$line" in
			@name\ *)
				name="${line#@name }"
			;;
			@conflicts\ *)
				conflicts="$conflicts${conflicts:+$IFS}${line#@conflicts }"
			;;
			@pkgdep\ *)
				depNames="$depNames${depNames:+$IFS}${line#@pkgdep }"
			;;
			@comment\ *)
				line="${line#@comment }"
				case "$line" in
					DEPORIGIN:*)
						dependencies="$dependencies${dependencies:+$IFS}${line#*:}"
					;;
					PKG_FORMAT_REVISION:*)
						format="${line#*:}"
					;;
					ORIGIN:*)
						origin="${line#*:}"
					;;
				esac
			;;
		esac

	done

	# Return values.
	$caller.setvar "$1" "$name"
	$caller.setvar "$2" "$origin"
	$caller.setvar "$3" "$dependencies"
	$caller.setvar "$4" "$depNames"
	$caller.setvar "$5" "$conflicts"

	# Perform a package format check.
	if [ "$format" != "1.1" ]; then
		bsda_pkg_errno=$bsda_pkg_ERR_PACKAGE_CONTENTS_FORMAT
		return 1
	fi

	return 0
}



#
# Instances of this class represent a package created from an index line or
# package file.
#
# Apart of being a storage for name and origin of the package it can provide
# references to all dependencies. This uses a lazy approach (which actually
# means more work for the programmer), meaning that the dependencies are
# only acquired and buffered when actually requested.
#
bsda:obj:createClass bsda:pkg:Package \
	r:private:index \
		"The Index instance this Package was created by." \
	-:dependencies \
		"A buffer for the list of dependencies." \
	-:update \
		"Result buffer for the isUpdate() method." \
	-:reinstall \
		"Result buffer for the isReinstall() method." \
	-:installed \
		"Result buffer for the isInstalled() method." \
	r:private:depNames \
		"A list of dependency names." \
	r:public:origin \
		"The package origin." \
	r:public:name \
		"The package name." \
	r:public:moved \
		"A list of package orgins moved to this package." \
	r:private:file \
		"The File instance this package was created from." \
	i:protected:init \
		"The constructor, initializes all the attributes." \
	x:public:getDependencies \
		"Returns the indexed dependencies of the Package." \
	x:public:addMoved \
		"Tell the package that it was moved from another origin." \
	x:public:isUpdate \
		"Check whether this is an update to an installed package." \
	x:public:isReinstall \
		"Check whether this is a reinstall without version changes." \
	x:public:isInstalled \
		"Check whether a version of this package is installed." \
	x:public:fetch \
		"Fetch a package if necessary." \
	x:public:verify \
		"Verify the package file and adopt it." \

#
# The constructor initializes all the attributes.
#
# The dependencies attribute is set to null to indicate that the dependencies
# have not yet been buffered. An empty buffer would imply that the package
# has no dependencies.
#
# The fourth parameter is the source this package was created from. This
# is either a file or an index line.
#
# @param 1
#	The Index instance this Package was created by.
# @param 2
#	The origin of the package.
# @param 3
# 	The name of the package.
# @param 4
#	Either the File or the index line this package was created from.
#
bsda:pkg:Package.init() {
	local IFS
	IFS='
'
	setvar ${this}index $1
	setvar ${this}dependencies null
	setvar ${this}origin "$2"
	setvar ${this}name "$3"
	# Set file or index line as source.
	if bsda:pkg:File.isInstance "$4"; then
		setvar ${this}file "$4"
		setvar ${this}depNames
	else
		setvar ${this}file
		setvar ${this}depNames "$(echo "$4" | /usr/bin/cut -d\| -f$bsda_pkg_IDX_DEPENDS | /usr/bin/sed "s/ /\\$IFS/g")"
	fi
}

#
# Returns the dependencies of a package to a variable.
#
# @param 1
#	The name of the variable to store the list of dependencies in.
# @throws bsda_pkg_ERR_PACKAGE_FORMAT
#	This error is set if the package format version is not 1.1.
#
bsda:pkg:Package.getDependencies() {
	local file dependencies null index
	$this.getIndex index

	# Check whether the buffer is already filled.
	if eval "test \"\$${this}dependencies\" = 'null'"; then
		# The buffer needs filling.

		# Check whether a package file is available.
		$this.getFile file
		if [ -n "$file" ]; then
			# A package file is available.
			if ! $file.getContents null null dependencies null null; then
				# Forward errors.
				return 1
			fi
			eval "$index.getPackagesByOrigins ${this}dependencies \"$dependencies\""
		else
			# A package file is not available, use the index line
			# provided dependency names.
			$this.getDepNames dependencies
			eval "$index.getPackagesByNames ${this}dependencies \"$dependencies\""
		fi
	fi

	# Return the list of dependencies.
	eval "
	$caller.setvar '$1' \"\$${this}dependencies\"
	$this.getDependencies() {
		setvar '$1' \"\$${this}dependencies\" 2> /dev/null || echo \"\$${this}dependencies\"
	}
	"
}

#
# Add the origins of packages to be replaced with this package.
#
# @param @
#	The package origins to replace.
#
bsda:pkg:Package.addMoved() {
	local IFS moved origin
	IFS='
'
	$this.getMoved moved
	for origin in "$@"; do
		moved="${moved:+$moved$IFS}$origin"
	done
	setvar ${this}moved "$moved"
}

#
# Checks if this is an update or a missing package.
#
# @return
#	True (0) if this is an update or missing, else false (1).
#
bsda:pkg:Package.isUpdate() {
	if eval "[ -z \"\$${this}update\" ]"; then
		local IFS origins origin name installedName

		IFS='
'
		$this.getName name
		$this.getOrigin origin

		# Treat missing packages and real updates as such.
		installedName="$(/usr/sbin/pkg_info -qO "$origin")"
		test -z "$installedName" || test "$(/usr/sbin/pkg_version -t "$installedName" "$name")" = "<"
		setvar ${this}update $?
	fi
	eval "
	$this.isUpdate() {
		return \$${this}update
	}
	return \$${this}update
	"
}

#
# Checks whether this is a reinstall without version changes.
#
# @return
#	True (0) if this is a plain reinstall of an exisiting package,
#	false (1) otherwise.
#
bsda:pkg:Package.isReinstall() {
	if eval "[ -z \"\$${this}reinstall\" ]"; then
		local name
		$this.getName name
		# Returns false (1) if the name is not found.
		/usr/sbin/pkg_info -Eq "$name"
		setvar ${this}reinstall $?
	fi
	eval "
	$this.isReinstall() {
		return \$${this}reinstall
	}
	return \$${this}reinstall
	"
}

#
# Checks whether a version of this package is installed.
#
# Unlike isReinstall() any version is accepted.
#
# @return
#	True (0) if a version of this package is already installed,
#	false (1) otherwise.
#
bsda:pkg:Package.isInstalled() {
	if eval "[ -z \"\$${this}installed\" ]"; then
		local origin
		$this.getOrigin origin
		# Returns true (0) if the origin is found.
		test -n "$(/usr/sbin/pkg_info -qO "$origin")"
		setvar ${this}installed $?
	fi
	eval "
	$this.isInstalled() {
		return \$${this}installed
	}
	return \$${this}installed
	"
}

#
# Fetch a package file if not present.
#
# If no download manager is present or the package is already paired with a
# file, this will just tell the index that the file download was completed.
#
# If the present file's dependencies do not match the INDEX line (if the
# package was created from the INDEX), the file will be synchronized with
# the servers.
#
bsda:pkg:Package.fetch() {
	local index suffix dir downloader file job presentFile depNamesExpected
	local depNamesFile null

	$this.getIndex index

	# Check whether this already has a file.
	$this.getFile file
	if [ -n "$file" ]; then
		$index.downloadStarted
		return 0
	fi

	$index.getDownloader downloader

	# Check for downloader.
	if [ -z "$downloader" ]; then
		# Nothing to be done.
		$index.downloadStarted
		return 0
	fi

	# Get file and path names.
	$index.getFileSuffix suffix
	$index.getFileDir dir
	$this.getName file
	file="$file$suffix"
	if [ -r "$dir/$file" ]; then
		# File exists, check dependencies.
		$this.getDepNames depNamesExpected
		bsda:pkg:File presentFile "$dir/$file"
		# Get the dependency names from the present file.
		if ! $presentFile.getContents null null null depNamesFile null; then
			# Throw exceptions away.
			bsda_pkg_errno=0
		fi
		# Throw the present file object away. Pairing would be,
		# possible now, but then dependencies would have to be
		# thrown instead of discarded.
		$presentFile.delete
		# Check whether all expected dependencies were listed by the
		# file, with the exact same name and version.
		if [ -z "$(echo "$depNamesExpected" | /usr/bin/grep -vxF "$depNamesFile")" ]; then
			# Register the successful download
			$index.downloadStarted
			return 0
		fi
		# Remove the outdated file, to make sure that it fails if
		# there is no network connection.
		/bin/rm "$dir/$file"
	fi
		

	# Dispatch the download job.
	$downloader.createJob job "$file" "$dir/$file"
	setvar ${this}download $job

	# Tell the index about this download.
	$index.downloadStarted $job
}

#
# Checks whether the given package has a readable package file and
# whether tar accepts it as an archive.
#
# After the verification the final pairing with the file is done,
# as if the package was originally created from that file.
#
# @param &1
#	The name of the variable to store the name of the verified file in.
# @throws bsda_pkg_ERR_FILE_MISSING
#	The package file is not present.
# @throws bsda_pkg_ERR_FILE_INVALID
#	The file is not a package file.
#
bsda:pkg:Package.verify() {
	local file index suffix dir
	
	# Check whether this already has a file.
	$this.getFile file
	if [ -n "$file" ]; then
		# This file is already verified.
		$file.getFile file
		$caller.setvar "$1" "$file"
		return 0
	fi

	# Get file and path names.
	$index.getFileSuffix suffix
	$index.getFileDir dir
	$this.getName file
	file="$dir/$file$suffix"

	# Return the file, no matter what happens.
	$caller.setvar "$1" "$file"

	if [ ! -r "$file" ]; then
		# The file is missing!
		bsda_pkg_errno=$bsda_pkg_ERR_FILE_MISSING
		return 1
	fi

	# Check whether this is a tar archive containing a +CONTENTS file.
	if ! /usr/bin/tar -qtf "$file" +CONTENTS 2>&1 > /dev/null; then
		# The file is not a package file!
		bsda_pkg_errno=$bsda_pkg_ERR_FILE_INVALID
		return 1
	fi

	# Create the new file.
	bsda:pkg:File ${this}file "$file"
	setvar ${this}file
	return 0
}

#
# Instances of this class represent a MOVED file.
#
bsda:obj:createClass bsda:pkg:Moved \
	r:private:moved \
		"The MOVED file name." \
	i:private:init \
		"Constructor." \
	x:protected:search \
		"Search in the MOVED file." \

#
# The constructor for a MOVED file object.
#
# @param 1
#	The MOVED file name.
# @throws bsda_pkg_ERR_MOVED_FILE_MISSING
#	Is thrown if the first parameter is not a readable file.
#
bsda:pkg:Moved.init() {
	if [ ! -r "$1" ]; then
		bsda_pkg_errno=$bsda_pkg_ERR_MOVED_FILE_MISSING
		return 1
	fi
	setvar ${this}moved "$1"
}

#
# Search in the moved file. This returns the conents of the
# last matching line in a moved file.
#
# @param 1
#	The name of the variable to store matches in.
# @param 2
#	The column to search in.
# @param 3
#	A list of search strings.
# @param 4
#	The optional column to return, if left blank the entire moved line
#	is returned.
#
bsda:pkg:Moved.search() {
	local moved lines

	$this.getMoved moved

	# Get the matching lines/columns from the MOVED file.
	lines="$(/usr/bin/awk -F\| "
		BEGIN {
			# Create an array with the requested strings as
			# indices.
			$(echo "$3" | sed -e 's/^/search["/1' -e 's/$/"]/1')
		}

		\$$2 in search {
			# Store matching lines. This is necessary because
			# only the last matching line for each search entry
			# should be returned.
			search[\$$2] = \$${4:-0}
		}

		END {
			# Print the matching lines.
			for (i in search)
				if (search[i] != \"\")
					print search[i]
		}
	" "$moved")"

	# Return the matching moved lines.
	$caller.setvar "$1" "$lines"
	return 0
}

