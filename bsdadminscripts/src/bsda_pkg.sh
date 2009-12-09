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
. bsda_obj.sh

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

# Index exceptions.
readonly bsda_pkg_ERR_INDEX_FILE_MISSING=7
readonly bsda_pkg_ERR_INDEX_MOVED_MISSING=8

# Moved exceptions.
readonly bsda_pkg_ERR_MOVED_FILE_MISSING=9

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
# into the index representation. This indexed and unindexed packages can
# be handled through a single interface.
#
bsda:obj:createClass bsda:pkg:Index \
	r:private:index	\
		"INDEX filename." \
	r:private:moved \
		"A Moved instance." \
	r:private:originPrefix \
		"The ports directory used for building the packages." \
	r:private:packages \
		"The packages already read from the index." \
	r:private:mappedPackages \
		"The same list as packages only mapped by package origin" \
		"in the format: |<origin>|<Package>" \
	r:private:originBlacklist \
		"A list of unavailable encountered origins." \
	i:private:init \
		"Constructor." \
	x:private:search \
		"Returns index lines matching a given string and column." \
	x:public:identifyPackages \
		"Returns a list of packages by a given glob pattern." \
	x:private:identifyOrigins \
		"Returns a list of packages from an origin glob pattern." \
	x:private:identifyNames \
		"Returns a list of packages from a package name glob pattern." \
	x:protected:getPackagesByOrigins \
		"Takes a list of origins and returns a list of Packages." \
	x:protected:getPackagesByNames \
		"Takes a list of package names and returns" \
		"a list of Packages." \
	x:private:addPackages \
		"Adds packages to the packages list." \
	x:private:getKnownPackages \
		"Gets already known packages by origin." \

#
# The constructor for an index interface object.
#
# @param 1
#	The INDEX file name.
# @param 2
#	The Moved instances.
# @throws bsda_pkg_ERR_INDEX_FILE_MISSING
#	Is thrown if parameter one is not a file.
# @throws bsda_pkg_ERR_INDEX_MOVED_MISSING
#	Is thrown if the second parameter is not a bsda:pkg:Moved object.
#
bsda:pkg:Index.init() {
	local origin
	if [ ! -f "$1" ]; then
		bsda_pkg_errno=$bsda_pkg_ERR_INDEX_FILE_MISSING
		return 1
	fi
	setvar ${this}index "$1"
	origin="$(head -n1 "$1"| cut -d\| -f$bsda_pkg_IDX_ORIGIN)"
	setvar ${this}originPrefix "${origin%/*/*}/"
	if ! bsda:pkg:Moved.isInstance "$2"; then
		bsda_pkg_errno=$bsda_pkg_ERR_INDEX_MOVED_MISSING
		return 1
	fi
	setvar ${this}moved $2
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
	length=$(echo "$3" | wc -l)

	# Get the matching index lines.
	lines="$(echo "
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
	" | awk -F\| -f - "$index")"

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
		if ! $file.getContents name origin null null; then
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
			# Reset the matching package.
			$pkg.reset
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
	if ! echo "$2" | grep -qE '\*|\?|\[.*]'; then
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
	if echo "$2" | grep -qE '\*|\?|\[.*]'; then
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
# Takes a list of origins and returns a list of Package instance. If the
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
	local IFS packages origins origin pkg prefix index name newPackages
	local lines line blacklist missing moved

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

	# Get the index file.
	$this.getIndex index
	# Get the Moved instances.
	$this.getMoved moved

	#
	# Try to create new Package instances for the remaining origins.
	#

	$this.search lines $bsda_pkg_IDX_ORIGIN "$(echo "$missing" | sed "s|^|$prefix|1")"
	# Collect available origins.
	origins=
	# Create packages.
	for line in $lines; {
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
	}

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
	local oldorigin neworigin

	$moved.search lines $bsda_pkg_MOV_OLDORIGIN "$missing"
	# Collect the available origins to remove from the
	# list of missing packages.
	origins=
	# Try to get the packages. This cannot be done in a
	# single chunk, which would benefit performance, because
	# the original origin would be lost. This would break
	# blacklisting.
	for line in $lines; {
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

		# There actually is a package, remember it.
		packages="$packages${packages:+$IFS}$pkg"
		# Create an alias with the old origin.
		eval "${this}mappedPackages=\"\$${this}mappedPackages\${${this}mappedPackages:+\$IFS}|$oldorigin|$pkg\""
		# Remember the old origin to remove it from
		# the list of missing packages.
		origins="$origins${origins:+$IFS}$oldorigin"
	}
	

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
	local index prefix numbers origins packages
	$this.getOriginPrefix prefix
	$this.getIndex index

	# Get the origins from the index.
	$this.search origins $bsda_pkg_IDX_PKG "$2" $bsda_pkg_IDX_ORIGIN
	origins="$(echo "$origins" | sed "s|$prefix||1")"

	# Forward the list of of origins to the getPackagesByOrigins() method.
	$this.getPackagesByOrigins packages "$origins"
	# Return the Package instances.
	$caller.setvar "$1" "$packages"
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
	for pkg in $1; {
		eval "${this}mappedPackages=\"\$${this}mappedPackages\${${this}mappedPackages:+\$IFS}|$($pkg.getOrigin)|$pkg\""
	}
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
	local pkg origins origin packages

	# The list of packages.
	packages=
	# The list of matched origins.
	origins=

	# Fetch all available origins from the list of already existing
	# packages.
	for pkg in $($this.getMappedPackages | grep -F "$(echo "$3" | sed -e 's/^/|/1' -e 's/$/|/1')"); {
		# Fetch origin and Package instance from the mappedPackage line.
		origin="${pkg%|*}"
		origin="${origin#|}"
		pkg="${pkg##*|}"

		# Store the match.
		packages="$packages${packages:+$IFS}$pkg"

		# Add the current origin to the list of encountered origins.
		origins="$origins${origins:+$IFS}$origin"
	}

	# Return the matched packages.
	$caller.setvar "$1" "$packages"

	# Return a list of missing origins.
	$caller.setvar "$2" "$(echo "$3" | grep -vFx "$origins")"
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
# @param 1
#	The name of the variable the name should be stored in.
# @param 2
#	The name of the variable the origin should be stored in.
# @param 3
#	The name of the variable the dependencies, as a list of origins,
#	should be stored in.
# @param 4
#	The name of the variable the conflict patters should be stored in.
# @throws bsda_pkg_ERR_PACKAGE_CONTENTS_FORMAT
#	This error is set if the package format version is not 1.1.
#
bsda:pkg:File.getContents() {
	local IFS file line format name orgin dependencies conflicts

	IFS='
'

	$this.getFile file

	name=
	origin=
	dependencies=
	conflicts=

	# Process the +CONTENTS file in the tar archive line by line.
	for line in $(tar -xOf "$file" '+CONTENTS'); {
		case "$line" in
			@name\ *)
				name="${line#@name }"
			;;
			@conflicts\ *)
				conflicts="$conflicts${conflicts:+$IFS}${line#@conflicts }"
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

	}

	# Return values.
	$caller.setvar "$1" "$name"
	$caller.setvar "$2" "$origin"
	$caller.setvar "$3" "$dependencies"
	$caller.setvar "$4" "$conflicts"

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
	r:public:origin \
		"The package origin." \
	r:public:name \
		"The package name." \
	r:private:file \
		"The File instance this package was created from." \
	r:private:line \
		"The index line this package was created from." \
	i:protected:init \
		"The constructor, initializes all the attributes." \
	x:public:getDependencies \
		"Returns the indexed dependencies of the Package." \

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
	setvar ${this}index $1
	setvar ${this}dependencies null
	setvar ${this}origin "$2"
	setvar ${this}name "$3"
	# Set file or index line as source.
	if bsda:pkg:File.isInstance "$4"; then
		setvar ${this}file "$4"
	else
		setvar ${this}line "$4"
	fi
}

#
# Returns the dependencies of a packages to a variable.
#
# @param 1
#	The name of the variable to store the list of dependencies in.
# @throws bsda_pkg_ERR_PACKAGE_FORMAT
#	This error is set if the package format version is not 1.1.
#
bsda:pkg:Package.getDependencies() {
	local file line dependencies null index
	$this.getIndex index

	# Check whether the buffer is already filled.
	if eval "test \"\$${this}dependencies\" = 'null'"; then
		# The buffer needs filling.

		# Check whether a package file is available.
		$this.getFile file
		if bsda:pkg:File.isInstance "$file"; then
			# A package file is available.
			if ! $file.getContents null null dependencies null; then
				# Forward errors.
				return 1
			fi
			eval "$index.getPackagesByOrigins ${this}dependencies \"$dependencies\""
		else
			# A package file is not available, use the index line.
			$this.getLine line
			dependencies="$(echo "$line" | cut -d\| -f$bsda_pkg_IDX_DEPENDS | rs 0 1)"
			eval "$index.getPackagesByNames ${this}dependencies \"$dependencies\""
	
			# The index line is no longer needed and just wastes memory.
			unset ${this}line
		fi
	fi

	# Return the list of dependencies.
	eval "$caller.setvar '$1' \"\$${this}dependencies\"" 
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
#	Is thrown if the first parameter is not a file.
#
bsda:pkg:Moved.init() {
	if [ ! -f "$1" ]; then
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
	lines="$(awk -F\| "
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

