#!/bin/sh

# Test case: Try to establish TLS connections with gnutls-cli and
# check the validity of the server certificate via OCSP
#
# Copyright (C) 2016 Thomas Klute
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

: ${srcdir=.}
: ${CERTTOOL=../src/certtool${EXEEXT}}
: ${OCSPTOOL=../src/ocsptool${EXEEXT}}
: ${SERV=../src/gnutls-serv${EXEEXT}}
: ${CLI=../src/gnutls-cli${EXEEXT}}
: ${DIFF=diff}
TEMPLATE_FILE="out.$$.tmpl.tmp"
SERVER_CERT_FILE="cert.$$.pem.tmp"

if ! test -x "${CERTTOOL}"; then
	exit 77
fi

if ! test -x "${OCSPTOOL}"; then
	exit 77
fi

if ! test -x "${SERV}"; then
	exit 77
fi

if ! test -x "${CLI}"; then
	exit 77
fi

if ! test -z "${VALGRIND}"; then
	VALGRIND="${LIBTOOL:-libtool} --mode=execute ${VALGRIND} --error-exitcode=15"
fi

export TZ="UTC"

. "${srcdir}/scripts/common.sh"

skip_if_no_datefudge

eval "${GETPORT}"
# Port for gnutls-serv
TLS_SERVER_PORT=$PORT

# Port to use for OCSP server, must match the OCSP URI set in the
# server_*.pem certificates
eval "${GETPORT}"
OCSP_PORT=$PORT

# Maximum timeout for server startup (OCSP and TLS)
SERVER_START_TIMEOUT=10

# Check for OpenSSL
: ${OPENSSL=openssl}
if ! ("$OPENSSL" version) > /dev/null 2>&1; then
    echo "You need openssl to run this test."
    exit 77
fi

CERTDATE="2016-04-28"
TESTDATE="2016-04-29"

OCSP_PID=""
TLS_SERVER_PID=""
stop_servers ()
{
    test -z "${OCSP_PID}" || kill "${OCSP_PID}"
    test -z "${TLS_SERVER_PID}" || kill "${TLS_SERVER_PID}"
    rm -f "$TEMPLATE_FILE"
    rm -f "$SERVER_CERT_FILE"
}
trap stop_servers 1 15 2 EXIT

echo "=== Generating good server certificate ==="

rm -f "$TEMPLATE_FILE"
cp "${srcdir}/ocsp-tests/certs/server_good.template" "$TEMPLATE_FILE"
chmod u+w "$TEMPLATE_FILE"
echo "ocsp_uri=http://localhost:${OCSP_PORT}/ocsp/" >>"$TEMPLATE_FILE"

# Generate certificates with the random port
datefudge -s "${CERTDATE}" ${CERTTOOL} \
	--generate-certificate --load-ca-privkey "${srcdir}/ocsp-tests/certs/ca.key" \
	--load-ca-certificate "${srcdir}/ocsp-tests/certs/ca.pem" \
	--load-privkey "${srcdir}/ocsp-tests/certs/server_good.key" \
	--template "${TEMPLATE_FILE}" --outfile "${SERVER_CERT_FILE}" 2>/dev/null

echo "=== Bringing OCSP server up ==="

# Start OpenSSL OCSP server
#
# WARNING: As of version 1.0.2g, OpenSSL OCSP cannot bind the TCP port
# if started repeatedly in a short time, probably a lack of
# SO_REUSEADDR usage.
PORT=${OCSP_PORT}
launch_bare_server \
	  datefudge "${TESTDATE}" \
	  "${OPENSSL}" ocsp -index "${srcdir}/ocsp-tests/certs/ocsp_index.txt" -text \
	  -port "${OCSP_PORT}" \
	  -rsigner "${srcdir}/ocsp-tests/certs/ocsp-server.pem" \
	  -rkey "${srcdir}/ocsp-tests/certs/ocsp-server.key" \
	  -CA "${srcdir}/ocsp-tests/certs/ca.pem"
OCSP_PID="${!}"
wait_server "${OCSP_PID}"

echo "=== Verifying OCSP server is up ==="

# Port probing (as done in wait_port) makes the OpenSSL OCSP server
# crash due to the "invalid request", so try proper requests
t=0
while test "${t}" -lt "${SERVER_START_TIMEOUT}"; do
    # Run a test request to make sure the server works
    datefudge "${TESTDATE}" \
	      ${VALGRIND} "${OCSPTOOL}" --ask \
	      --load-cert "${SERVER_CERT_FILE}" \
	      --load-issuer "${srcdir}/ocsp-tests/certs/ca.pem"
    rc=$?
    if test "${rc}" = "0"; then
	break
    else
	t=`expr ${t} + 1`
	sleep 1
    fi
done
# Fail if the final OCSP request failed
if test "${rc}" != "0"; then
    echo "OCSP server check failed."
    exit ${rc}
fi

echo "=== Test 1: Server with valid certificate ==="

PORT=${TLS_SERVER_PORT}
launch_bare_server \
	  datefudge "${TESTDATE}" \
	  "${SERV}" --echo --disable-client-cert \
	  --x509keyfile="${srcdir}/ocsp-tests/certs/server_good.key" \
	  --x509certfile="${SERVER_CERT_FILE}" \
	  --port="${TLS_SERVER_PORT}"
TLS_SERVER_PID="${!}"
wait_server $TLS_SERVER_PID

wait_for_port "${TLS_SERVER_PORT}"

echo "test 123456" | \
    datefudge -s "${TESTDATE}" \
	      "${CLI}" --ocsp --x509cafile="${srcdir}/ocsp-tests/certs/ca.pem" \
	      --port="${TLS_SERVER_PORT}" localhost
rc=$?

if test "${rc}" != "0"; then
    echo "Connecting to server with valid certificate failed."
    exit ${rc}
fi

kill "${TLS_SERVER_PID}"
wait "${TLS_SERVER_PID}"
unset TLS_SERVER_PID

echo "=== Generating bad server certificate ==="

rm -f "${SERVER_CERT_FILE}"
rm -f "${TEMPLATE_FILE}"
cp "${srcdir}/ocsp-tests/certs/server_bad.template" "$TEMPLATE_FILE"
echo "ocsp_uri=http://localhost:${OCSP_PORT}/ocsp/" >>"$TEMPLATE_FILE"

# Generate certificates with the random port
datefudge -s "${CERTDATE}" ${CERTTOOL} \
	--generate-certificate --load-ca-privkey "${srcdir}/ocsp-tests/certs/ca.key" \
	--load-ca-certificate "${srcdir}/ocsp-tests/certs/ca.pem" \
	--load-privkey "${srcdir}/ocsp-tests/certs/server_bad.key" \
	--template "${TEMPLATE_FILE}" --outfile "${SERVER_CERT_FILE}"

echo "=== Test 2: Server with revoked certificate ==="

eval "${GETPORT}"
TLS_SERVER_PORT=$PORT

launch_bare_server \
	  datefudge "${TESTDATE}" \
	  "${SERV}" --echo --disable-client-cert \
	  --x509keyfile="${srcdir}/ocsp-tests/certs/server_bad.key" \
	  --x509certfile="${SERVER_CERT_FILE}" \
	  --port="${TLS_SERVER_PORT}"
TLS_SERVER_PID="${!}"
wait_server ${TLS_SERVER_PID}
wait_for_port "${TLS_SERVER_PORT}"

echo "test 123456" | \
    datefudge -s "${TESTDATE}" \
	      "${CLI}" --ocsp --x509cafile="${srcdir}/ocsp-tests/certs/ca.pem" \
	      --port="${TLS_SERVER_PORT}" localhost
rc=$?

kill "${TLS_SERVER_PID}"
wait "${TLS_SERVER_PID}"
unset TLS_SERVER_PID

# This connection should not work because the certificate has been
# revoked.
if test "${rc}" = "0"; then
    echo "Connecting to server with revoked certificate succeeded."
    exit 1
fi

kill ${OCSP_PID}
wait ${OCSP_PID}
unset OCSP_PID

rm -f "${SERVER_CERT_FILE}"
rm -f "${TEMPLATE_FILE}"

exit 0
