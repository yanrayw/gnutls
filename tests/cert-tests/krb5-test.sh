#!/bin/sh

# Copyright (C) 2015 Red Hat, Inc.
#
# This file is part of GnuTLS.
#
# GnuTLS is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3 of the License, or (at
# your option) any later version.
#
# GnuTLS is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GnuTLS.  If not, see <https://www.gnu.org/licenses/>.

#set -e

: ${srcdir=.}
: ${CERTTOOL=../../src/certtool${EXEEXT}}
: ${DIFF=diff}
OUTFILE=tmp-krb5name.pem
TMPLFILE=tmp-krb5name.tmpl

if ! test -x "${CERTTOOL}"; then
	exit 77
fi

export TZ="UTC"

. ${srcdir}/../scripts/common.sh

skip_if_no_datefudge

if ! test -z "${VALGRIND}"; then
	ORIG_VALGRIND=${VALGRIND}
	VALGRIND="${LIBTOOL:-libtool} --mode=execute ${VALGRIND} --error-exitcode=3"
fi

# Note that in rare cases this test may fail because the
# time set using datefudge could have changed since the generation
# (if example the system was busy)

datefudge -s "2007-04-22" \
	"${CERTTOOL}" --generate-self-signed \
		--load-privkey "${srcdir}/data/template-test.key" \
		--template "${srcdir}/templates/template-krb5name.tmpl" \
		--outfile ${OUTFILE} 2>/dev/null

${DIFF} "${srcdir}/data/template-krb5name.pem" ${OUTFILE} >/dev/null 2>&1
rc=$?

# We're done.
if test "${rc}" != "0"; then
	echo "Test 1 failed"
	exit ${rc}
fi

# disable all parameters to valgrind, to prevent memleak checking on
# the following tests (negative tests which have leaks in the tools).
if ! test -z "${ORIG_VALGRIND}"; then
	VALGRIND=$(echo ${ORIG_VALGRIND}|cut -d ' ' -f 1)
	VALGRIND="${LIBTOOL:-libtool} --mode=execute ${VALGRIND} --error-exitcode=3"
fi

# Negative tests. Check against values which may cause problems
cp "${srcdir}/templates/template-krb5name.tmpl" ${TMPLFILE}
echo "krb5_principal = 'xxxxxxxxxxxxxx'" >>${TMPLFILE}

datefudge -s "2007-04-22" \
${VALGRIND} "${CERTTOOL}" --generate-self-signed \
		--load-privkey "${srcdir}/data/template-test.key" \
		--template ${TMPLFILE} \
		--outfile ${OUTFILE} 2>/dev/null

rc=$?

# We're done.
if test "${rc}" != "1"; then
	echo "Negative Test 1 failed"
	exit ${rc}
fi

cp "${srcdir}/templates/template-krb5name.tmpl" ${TMPLFILE}
echo "krb5_principal = 'comp1/comp2/comp3/comp4/comp5/comp6/comp7/comp8/comp9/comp10@REALM.COM'" >>${TMPLFILE}

datefudge -s "2007-04-22" \
${VALGRIND} "${CERTTOOL}" --generate-self-signed \
		--load-privkey "${srcdir}/data/template-test.key" \
		--template ${TMPLFILE} \
		--outfile ${OUTFILE} 2>/dev/null

rc=$?

# We're done.
if test "${rc}" != "1"; then
	echo "Negative Test 2 failed"
	exit ${rc}
fi

rm -f ${OUTFILE}
rm -f ${TMPLFILE}

exit 0
