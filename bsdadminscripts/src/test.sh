#!/bin/sh -f
bsda_dir="${0%${0##*/}}"
. ${bsda_dir:-.}/bsda_pkg.sh
echo "dir: $bsda_dir"
echo "interpreter: $bsda_obj_interpreter"
bsda:pkg:Moved moved /var/db/uma/FTPMOVED
bsda:pkg:Index index /var/db/uma/FTPINDEX $moved
#$index.identifyPackages pkgs '*'
#for pkgname in $(pkg_info -qoa | head -n 100); do
#	$index.identifyPackages pkg "$pkgname"
#	$pkg.getOrigin
#done
#echo half
#for pkgname in $(pkg_info -qoa); do
#	if ! $index.identifyPackages pkg "$pkgname"; then
#		bsda_pkg_errno=0
#	else
#		$pkg.getOrigin
#	fi
#done | wc -l
#$index.identifyPackages pkgs '*/*'
