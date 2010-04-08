files="
automounter,0755,%%PREFIX%%/sbin/automounter
automounter.rc,0755,%%PREFIX%%/etc/rc.d/automounter
automounter.conf.sample,0644,%%PREFIX%%/etc/automounter.conf.sample
automounter.8,0644,%%MAN%%/man8/automounter.8.gz
automounter.conf.5,0644,%%MAN%%/man5/automounter.conf.5.gz
"

for parameter; {
	case "${parameter%%=*}" in
		-prefix | -var | -run | -tmp | -media | -devfs | -map | -amd | \
		-eli_images | -eli_keys)
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

: ${prefix=/usr/local}
: ${tmp=/tmp}
: ${var=/var}
: ${run=$var/run}
: ${vartmp=$var/tmp}
: ${media=/media}
: ${devfs=/dev}
: ${map=/etc/amd.map}
: ${amd=/usr/sbin/amd}
: ${geli_images=$var/geli/images}
: ${geli_keys=.geli/keys}

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
%%GELI_IMAGES%%,$geli_images
%%GELI_KEYS%%,$geli_keys
"

replace_cmd="sed"

IFS='
'

for substitution in $replace; {
	test -z "$substitution" && continue
	replace_cmd="$replace_cmd -e 's,$substitution,g'"
}

files="$(echo "$files" | eval "$replace_cmd")"

