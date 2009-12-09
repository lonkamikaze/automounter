. bsda_pkg.sh
bsda:pkg:Moved moved /var/db/uma/FTPMOVED
bsda:pkg:Index index /var/db/uma/FTPINDEX $moved
#$index.identifyPackages pkgs '*'
#for pkgname in $(pkg_info -qoa | head -n 100); {
#	$index.identifyPackages pkg "$pkgname"
#}
#echo half
#for pkgname in $(pkg_info -qoa); {
#	if ! $index.identifyPackages pkg "$pkgname"; then
#		bsda_pkg_errno=0
#	else
#		$pkg.getOrigin
#	fi
#} | wc -l
#$index.identifyPackages pkgs '*/*'
