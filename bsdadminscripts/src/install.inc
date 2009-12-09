: ${prefix=/usr/local}
: ${tmp=/tmp}
: ${awk=/usr/bin/awk}
: ${ports=/usr/ports}
: ${distdir=/usr/ports/distfiles}
: ${var=/var}
: ${datadir=$prefix/share/bsdadminscripts}

files="
bsdadminscripts.1,0644,%%MAN%%/man1/bsdadminscripts.1.gz
buildflags.awk,0755,%%DATADIR%%/buildflags.awk
buildflags.conf.sample,0644,%%PREFIX%%/etc/buildflags.conf.sample
buildflags.mk,0644,%%DATADIR%%/buildflags.mk
buildflags.awk.1,0644,%%MAN%%/man1/buildflags.awk.1.gz
buildflags.conf.1,0644,%%MAN%%/man1/buildflags.conf.1.gz
buildflags.mk.1,0644,%%MAN%%/man1/buildflags.mk.1.gz
distviper,0755,%%PREFIX%%/sbin/distviper
distviper.1,0644,%%MAN%%/man1/distviper.1.gz
pkg_libchk,0755,%%PREFIX%%/sbin/pkg_libchk
pkg_libchk.1,0644,%%MAN%%/man1/pkg_libchk.1.gz
pkg_upgrade,0755,%%PREFIX%%/sbin/pkg_upgrade
pkg_upgrade.1,0644,%%MAN%%/man1/pkg_upgrade.1.gz
pkg_upgrade.conf.sample,0644,%%PREFIX%%/etc/pkg_upgrade.conf.sample
pkg_validate,0755,%%PREFIX%%/sbin/pkg_validate
pkg_validate.1,0644,%%MAN%%/man1/pkg_validate.1.gz
portconfig,0755,%%PREFIX%%/sbin/portconfig
portconfig.1,0644,%%MAN%%/man1/portconfig.1.gz
rcstart,0755,%%PREFIX%%/sbin/rcstart
rcstart.1,0644,%%MAN%%/man1/rcstart.1.gz
uma,0755,%%PREFIX%%/sbin/uma
uma.1,0644,%%MAN%%/man1/uma.1.gz
uma.conf.sample,0644,%%PREFIX%%/etc/uma.conf.sample
"

links="
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rcstatus
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rcstop
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rcrestart
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rconestart
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rconestatus
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rconestop
%%PREFIX%%/sbin/rcstart,0755,%%PREFIX%%/sbin/rconerestart
%%PREFIX%%/sbin/portconfig,0755,%%PREFIX%%/sbin/portbuild
%%PREFIX%%/sbin/portconfig,0755,%%PREFIX%%/sbin/portclean
%%PREFIX%%/sbin/portconfig,0755,%%PREFIX%%/sbin/portfetch
%%PREFIX%%/sbin/portconfig,0755,%%PREFIX%%/sbin/portpackage
%%PREFIX%%/sbin/portconfig,0755,%%PREFIX%%/sbin/portconfig-recursive
%%PREFIX%%/sbin/portconfig,0755,%%PREFIX%%/sbin/portfetch-recursive
"

for parameter; {
	case "${parameter%%=*}" in
		-prefix)
			prefix="${parameter#*=}"
		;;
		-tmp)
			tmp="${parameter#*=}"
		;;
		-awk)
			awk="${parameter#*=}"
		;;
		-ports)
			ports="${parameter#*=}"
		;;
		-var)
			var="$${parameter#*=}"
		;;
		-distdir)
			distdir="${parameter#*=}"
		;;
		-datadir)
			datadir="${parameter#*=}"
		;;
		-nodoc)
			files="$(echo "$files" | grep -v '%%MAN%%')"
			links="$(echo "$links" | grep -v '%%MAN%%')"
		;;
		-nomancompress)
			files="$(echo "$files" | sed -E 's/(.*%%MAN%%.*\.[0-9]).gz$/\1/1')"
			links="$(echo "$links" | sed -E 's/(.*%%MAN%%.*\.[0-9]).gz$/\1/1')"
		;;
		*)
			echo "Unknown parameter '$parameter'." 1>&2
			return 1
		;;
	esac
}

replace="
%%PREFIX%%,$prefix
%%MAN%%,$prefix/man
%%TMP%%,$tmp
%%PORTS%%,$ports
%%DISTDIR%%,$distdir
%%AWK%%,$awk
%%VAR%%,$var
%%DATADIR%%,$datadir
"

replace_cmd="sed"

IFS='
'

for substitution in $replace; {
	test -z "$substitution" && continue
	replace_cmd="$replace_cmd -e 's,$substitution,g'"
}

files="$(echo "$files" | eval "$replace_cmd")"
links="$(echo "$links" | eval "$replace_cmd")"

