#!/bin/sh

# Copyright (C) 2006-2012 Free Software Foundation, Inc.
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
TMPFILE=sha3.$$.tmp

if ! test -x "${CERTTOOL}"; then
	exit 77
fi

export TZ="UTC"

. ${srcdir}/../scripts/common.sh

skip_if_no_datefudge

# Note that in rare cases this test may fail because the
# time set using datefudge could have changed since the generation
# (if example the system was busy)

# Test SHA3 signatures

for i in sha3-224 sha3-256 sha3-384 sha3-512;do
datefudge -s "2007-04-22" \
"${CERTTOOL}" --generate-self-signed \
		--load-privkey "${srcdir}/data/template-test.key" \
		--template "${srcdir}/templates/template-test.tmpl" \
		--outfile "${TMPFILE}" --hash $i 2>/dev/null
rc=$?

if test -f "${srcdir}/data/template-rsa-$i.pem";then
	${DIFF} "${srcdir}/data/template-rsa-$i.pem" "${TMPFILE}" >/dev/null 2>&1
	rc=$?
fi

# We're done.
if test "${rc}" != "0"; then
	echo "Test (RSA-$i) failed"
	exit ${rc}
fi

datefudge -s "2007-04-25" \
	"${CERTTOOL}" --load-ca-certificate "${TMPFILE}" --verify --infile "${TMPFILE}" >/dev/null 2>&1
rc=$?
if test "${rc}" != "0"; then
	echo "Test (verification of RSA-$i) failed"
	exit ${rc}
fi
done

# Test SHA3 signatures with ECDSA

for i in sha3-224 sha3-256 sha3-384 sha3-512;do
datefudge -s "2007-04-22" \
"${CERTTOOL}" --generate-self-signed \
	--load-privkey "${srcdir}/data/template-test-ecc.key" \
	--template "${srcdir}/templates/template-test.tmpl" \
	--outfile "${TMPFILE}" --hash $i 2>/dev/null
rc=$?

if test "${rc}" != "0"; then
	echo "Test (ECDSA-$i) failed"
	exit ${rc}
fi

datefudge -s "2007-04-25" \
	"${CERTTOOL}" --load-ca-certificate "${TMPFILE}" --verify --infile "${TMPFILE}" >/dev/null 2>&1
rc=$?
if test "${rc}" != "0"; then
	echo "Test (verification of ECDSA-$i) failed"
	exit ${rc}
fi
done

rm -f "${TMPFILE}"

exit 0
