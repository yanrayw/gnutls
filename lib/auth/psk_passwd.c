/*
 * Copyright (C) 2005-2012 Free Software Foundation, Inc.
 *
 * Author: Nikos Mavrogiannopoulos
 *
 * This file is part of GnuTLS.
 *
 * The GnuTLS is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1 of
 * the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>
 *
 */

/* Functions for operating in a PSK passwd file are included here */

#include "gnutls_int.h"

#include "x509_b64.h"
#include "errors.h"
#include <auth/psk_passwd.h>
#include <auth/psk.h>
#include "auth.h"
#include "dh.h"
#include "debug.h"
#include <str.h>
#include <datum.h>
#include <num.h>
#include <random.h>

static int read_prf_algo(const char *str, size_t len, gnutls_mac_algorithm_t *prf_algo)
{
	char algo_name[len + 1];
	gnutls_mac_algorithm_t prf;

	strncpy(algo_name, str, len);
	algo_name[len] = '\0';

	/* Some people are used to put dashes - make them happy */
	if (strcmp(algo_name, "SHA-1") == 0)
		strcpy(algo_name, "SHA1");
	else if (strcmp(algo_name, "SHA-256") == 0)
		strcpy(algo_name, "SHA256");
	else if (strcmp(algo_name, "SHA-512") == 0)
		strcpy(algo_name, "SHA512");
	else if (strcmp(algo_name, "SHA-224") == 0)
		strcpy(algo_name, "SHA224");
	else if (strcmp(algo_name, "SHA-384") == 0)
		strcpy(algo_name, "SHA384");

	if ((prf = gnutls_mac_get_id(algo_name)) == GNUTLS_MAC_UNKNOWN)
		return GNUTLS_E_KEYFILE_ERROR;

	*prf_algo = prf;
	return 0;
}

/* this function parses passwd.psk file. Format is:
 * string(username):hex(passwd)
 */
static int pwd_put_values(gnutls_datum_t * psk, gnutls_mac_algorithm_t *prf_algo, char *str)
{
	char *p, *p2;
	int len, ret;
	gnutls_datum_t tmp;

	p = strchr(str, ':');
	if (p == NULL) {
		gnutls_assert();
		return GNUTLS_E_SRP_PWD_PARSING_ERROR;
	}

	*p = '\0';
	p++;

	/* skip username
	 */

	/* read the key
	 */
	p2 = strchr(p, ':');

	if (p2)
		len = p2 - p;
	else
		len = strlen(p) - 1;

	tmp.data = (void*)p;
	tmp.size = len;
	ret = gnutls_hex_decode2(&tmp, psk);
	if (ret < 0) {
		gnutls_assert();
		return ret;
	}

	/* read the algorithm, if present and wanted by the user */
	if (p2 && prf_algo) {
		len = strlen(++p2);

		if (p2[len - 1] == '\n' || p2[len - 1] == ' ')
			len--;

		if ((ret = read_prf_algo(p2, len, prf_algo)) < 0) {
			gnutls_assert();
			return ret;
		}
	}

	return 0;

}


/* Randomizes the given password entry. It actually sets a random password. 
 * Returns 0 on success.
 */
static int _randomize_psk(gnutls_datum_t * psk)
{
	int ret;

	psk->data = gnutls_malloc(16);
	if (psk->data == NULL) {
		gnutls_assert();
		return GNUTLS_E_MEMORY_ERROR;
	}

	psk->size = 16;

	ret = gnutls_rnd(GNUTLS_RND_NONCE, (char *) psk->data, 16);
	if (ret < 0) {
		gnutls_assert();
		return ret;
	}

	return 0;
}

/* Returns the PSK key of the given user. 
 * If the user doesn't exist a random password is returned instead.
 */
int
_gnutls_psk_pwd_find_entry(gnutls_session_t session, char *username,
			   gnutls_datum_t * psk,
			   gnutls_mac_algorithm_t *prf_algo)
{
	gnutls_psk_server_credentials_t cred;
	FILE *fd;
	char *line = NULL;
	size_t line_size = 0;
	unsigned i, len;
	int ret;

	if (prf_algo)
		*prf_algo = GNUTLS_MAC_UNKNOWN;

	cred = (gnutls_psk_server_credentials_t)
	    _gnutls_get_cred(session, GNUTLS_CRD_PSK);
	if (cred == NULL) {
		gnutls_assert();
		return GNUTLS_E_INSUFFICIENT_CREDENTIALS;
	}

	/* if the callback which sends the parameters is
	 * set, use it.
	 */
	if (cred->pwd_callback != NULL) {
		ret = cred->pwd_callback(session, username, psk, prf_algo);

		if (ret == 1) {	/* the user does not exist */
			ret = _randomize_psk(psk);
			if (ret < 0) {
				gnutls_assert();
				return ret;
			}
			return 0;
		}

		if (ret < 0) {
			gnutls_assert();
			return GNUTLS_E_SRP_PWD_ERROR;
		}

		return 0;
	}

	/* The callback was not set. Proceed.
	 */
	if (cred->password_file == NULL) {
		gnutls_assert();
		return GNUTLS_E_SRP_PWD_ERROR;
	}

	/* Open the selected password file.
	 */
	fd = fopen(cred->password_file, "r");
	if (fd == NULL) {
		gnutls_assert();
		return GNUTLS_E_SRP_PWD_ERROR;
	}

	len = strlen(username);
	while (getline(&line, &line_size, fd) > 0) {
		/* move to first ':' */
		i = 0;
		while ((i < line_size) && (line[i] != '\0')
		       && (line[i] != ':')) {
			i++;
		}

		if (strncmp(username, line, MAX(i, len)) == 0) {
			ret = pwd_put_values(psk, prf_id, line);
			if (ret < 0) {
				gnutls_assert();
				ret = GNUTLS_E_SRP_PWD_ERROR;
				goto cleanup;
			}
			ret = 0;
			goto cleanup;
		}
	}

	/* user was not found. Fake him. 
	 */
	ret = _randomize_psk(psk);
	if (ret < 0) {
		goto cleanup;
	}

	ret = 0;
cleanup:
	if (fd != NULL)
		fclose(fd);

	zeroize_key(line, line_size);
	free(line);

	return ret;

}

/* returns the username and they key for the PSK session.
 * Free is non (0) if they have to be freed.
 */
int _gnutls_find_psk_key(gnutls_session_t session,
			 gnutls_psk_client_credentials_t cred,
			 gnutls_datum_t * username, gnutls_datum_t * key,
			 int *free)
{
	char *user_p;
	int ret;

	*free = 0;

	if (cred->username.data != NULL && cred->key.data != NULL) {
		username->data = cred->username.data;
		username->size = cred->username.size;
		key->data = cred->key.data;
		key->size = cred->key.size;
	} else if (cred->get_function != NULL) {
		ret = cred->get_function(session, &user_p, key);
		if (ret)
			return gnutls_assert_val(ret);

		username->data = (uint8_t *) user_p;
		username->size = strlen(user_p);

		*free = 1;
	} else
		return
		    gnutls_assert_val(GNUTLS_E_INSUFFICIENT_CREDENTIALS);

	return 0;
}
