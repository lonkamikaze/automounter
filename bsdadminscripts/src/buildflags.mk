#
# Copyright (c) 2006-2009
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
#
# version=1.11

# Default locations.
BUILDFLAGS_PARSER?=	%%DATADIR%%/buildflags.awk
BUILDFLAGS_CONF?=	%%PREFIX%%/etc/buildflags.conf
BUILDFLAGS_TMP?=	%%TMP%%/buildflags.tmp.mk.${USER}
BUILDFLAGS_GCC_CC?=	%%PREFIX%%/bin/gcc
BUILDFLAGS_GCC_CXX?=	%%PREFIX%%/bin/c++
BUILDFLAGS_GCC_CPP?=	%%PREFIX%%/bin/cpp

BUILDFLAGS_DISTCC?=	%%PREFIX%%/bin/distcc
BUILDFLAGS_CCACHE?=	%%PREFIX%%/bin/ccache

.if exists(${BUILDFLAGS_CONF})
# Parse configuration into a make file.
BUILDFLAGS!=		test "${BUILDFLAGS_TMP}" -nt "${BUILDFLAGS_CONF}" || "${BUILDFLAGS_PARSER}" "${BUILDFLAGS_CONF}" > "${BUILDFLAGS_TMP}"

# Include that make file.
.if exists(${BUILDFLAGS_TMP})
.include "${BUILDFLAGS_TMP}"
.endif
.endif

# Use a different version of gcc.
.if defined(WITH_GCC)
BUILDFLAGS_GCC?=	${WITH_GCC}
.if exists(${BUILDFLAGS_GCC_CC}${BUILDFLAGS_GCC}) 
CC:=			${BUILDFLAGS_GCC_CC}${BUILDFLAGS_GCC}
CXX:=			${BUILDFLAGS_GCC_CXX}${BUILDFLAGS_GCC}
CPP:=			${BUILDFLAGS_GCC_CPP}${BUILDFLAGS_GCC}
.endif
.endif

# Use distcc.
.if defined(USE_DISTCC) && !${CC:M*distcc*} && exists(${BUILDFLAGS_DISTCC}) && !(defined(USE_CCACHE) && !${CC:M*ccache*} && exists(${BUILDFLAGS_CCACHE}))
CC:=			${BUILDFLAGS_DISTCC} ${CC}
CPP:=			${BUILDFLAGS_DISTCC} ${CPP}
CXX:=			${BUILDFLAGS_DISTCC} ${CXX}
.endif

# Use ccache.
.if defined(USE_CCACHE) && !${CC:M*ccache*} && exists(${BUILDFLAGS_CCACHE}) && !(defined(USE_DISTCC) && !${CC:M*distcc*} && exists(${BUILDFLAGS_DISTCC}))
CC:=			${BUILDFLAGS_CCACHE} ${CC}
CPP:=			${BUILDFLAGS_CCACHE} ${CPP}
CXX:=			${BUILDFLAGS_CCACHE} ${CXX}
.endif

# Use ccache and distcc.
.if defined(USE_CCACHE) && !${CC:M*ccache*} && exists(${BUILDFLAGS_CCACHE}) && defined(USE_DISTCC) && !${CC:M*distcc*} && exists(${BUILDFLAGS_DISTCC})
CC:=			env CCACHE_PREFIX=${BUILDFLAGS_DISTCC} ${BUILDFLAGS_CCACHE} ${CC}
CPP:=			env CCACHE_PREFIX=${BUILDFLAGS_DISTCC} ${BUILDFLAGS_CCACHE} ${CPP}
CXX:=			env CCACHE_PREFIX=${BUILDFLAGS_DISTCC} ${BUILDFLAGS_CCACHE} ${CXX}
.endif

# Activate parallel builds for child makejobs.
.if defined(SUBTHREADS) && !(make(*install) || make(package))
.warning SUBTHREADS is deprecated in favour of the ports native settings FORCE_MAKE_JOBS and MAKE_JOBS_NUMBER
MAKE_ARGS:=		-j${SUBTHREADS}
.endif

# Activate normal parallel builds.
.if defined(THREADS)
.MAKEFLAGS:		-j${THREADS}
.endif
