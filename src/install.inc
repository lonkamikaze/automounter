files="
automounter,0755,%%PREFIX%%/sbin/automounter
automounter.rc,0755,%%PREFIX%%/etc/rc.d/automounter
automounter.conf.sample,0644,%%PREFIX%%/etc/automounter.conf.sample
devd.conf,0644,%%PREFIX%%/etc/devd/automounter.conf
automounter.8,0644,%%MAN%%/man8/automounter.8.gz
automounter.conf.5,0644,%%MAN%%/man5/automounter.conf.5.gz
"

for parameter; {
	case "${parameter%%=*}" in
	-destdir | -prefix | -tmp | -var | -run | -vartmp | -media | -devfs | \
	-map | -amd | -amq | -rpcbind | -rpcinfo | -logger | \
	-geli_images | -geli_keys)
		value="${parameter#*=}"
		parameter="${parameter%%=*}"
		parameter="${parameter#-}"
		eval "$parameter='$value'"
		;;
	-nodoc)
		files="$(echo "$files" | grep -v '%%MAN%%')"
		;;
	*)
		echo "Unknown parameter '$parameter'." 1>&2
		return 1
		;;
	esac
}

: ${destdir=}
: ${prefix=/usr/local}
: ${tmp=/tmp}
: ${var=/var}
: ${run=$var/run}
: ${vartmp=$var/tmp}
: ${media=/media}
: ${devfs=/dev}
: ${map=/etc/amd.map}
: ${amd=/usr/sbin/amd}
: ${amq=/usr/sbin/amq}
: ${rpcbind=/usr/sbin/rpcbind}
: ${rpcinfo=/usr/bin/rpcinfo}
: ${logger=/usr/bin/logger -st automounter}
: ${geli_images=$var/geli/images}
: ${geli_keys=.geli/keys}

# If set, destdir should end with a /
destdir=${destdir%/}${destdir:+/}

replace="
%%PREFIX%%,$prefix
%%MAN%%,$prefix/man
%%TMP%%,$tmp
%%RUN%%,$run
%%VARTMP%%,$vartmp
%%MEDIA%%,$media
%%DEVFS%%,$devfs
%%MAP%%,$map
%%AMD%%,$amd
%%AMQ%%,$amq
%%RPCBIND%%,$rpcbind
%%RPCINFO%%,$rpcinfo
%%LOGGER%%,$logger
%%GELI_IMAGES%%,$geli_images
%%GELI_KEYS%%,$geli_keys
"

replace_cmd="sed -e '/#HACK/,/#hack/d'"

IFS='
'

argsel() {
	i="$1"
	shift
	eval "echo \"\$$i\""
}

for substitution in $replace; {
	test -z "$substitution" && continue
	replace_cmd="$replace_cmd -e 's,$substitution,g'"
	for i in $(jot 9); do
		select="${substitution%%,*}"
		replace="${substitution#*,}"
		replace_cmd="$replace_cmd -e 's,${select%\%\%}:$i%%,$(eval argsel $i $replace),g'"
	done
}

files="$(echo "$files" | eval "$replace_cmd")"

