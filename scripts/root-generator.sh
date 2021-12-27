#!/usr/bin/env bash

# script-template.sh https://gist.github.com/m-radzikowski/53e0b39e9a59a1518990e76c2bff8038 by Maciej Radzikowski
# MIT License https://gist.github.com/m-radzikowski/d925ac457478db14c2146deadd0020cd
# https://betterdev.blog/minimal-safe-bash-script-template/

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# shellcheck disable=SC2034
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v]
This script can be used to generate a root certificate authority.
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-c, --config    OpenSSL configuration file
-d, --data-dir  Target directory where to store the CA
-e, --expiry    After how many days the certificate expires (default 7300)
-f, --force     WILL OVERWRITE EXISTING CERTIFICATE
-i, --city      City of the certificate authority
-l, --openssl   The path to the OpenSSL binary to use
-m, --email     E-Mail of the certificate authority
-n, --cname     Common name for the certificate authority
-o, --org       Organization of the certificate authority
-p, --pw        Supply the authority password
-s, --state     State/Province of the certificate authority
-t, --unit      Organizational Unit of the certificate authority
-u, --country   Country of the certificate authority
EOF
	exit
}

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	# script cleanup here
}

setup_colors() {
	if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
		NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
	else
		# shellcheck disable=SC2034
		NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
	fi
}

msg() {
	echo >&2 -e "${1-}"
}

die() {
	local msg=$1
	local code=${2-1} # default exit status 1
	msg "$msg"
	exit "$code"
}

parse_params() {
	# default values of variables set from params
	a_city=''
	a_cname=''
	a_country=''
	a_email=''
	a_organization=''
	a_state=''
	a_unit=''
	config=''
	data_dir=''
	expiry=7300
	force=0
	openssl=$(which openssl)
	pw="${SIMPLE_CA_ROOT_PASSWORD-}"
	verbose=0

	while :; do
		case "${1-}" in
		-h | --help) usage ;;
		-v | --verbose) set -x && verbose=1 ;;
		--no-color) NO_COLOR=1 ;;
		-c | --config)
			config="${2-}"
			shift
			;;
		-d | --data-dir)
			data_dir="${2-}"
			shift
			;;
		-e | --expiry)
			expiry="${2-}"
			shift
			;;
		-f | --force) force=1 ;;
		-i | --city)
			a_city="${2-}"
			shift
			;;
		-l | --openssl)
			openssl="${2-}"
			shift
			;;
		-m | --email)
			a_email="${2-}"
			shift
			;;
		-n | --cname)
			a_cname="${2-}"
			shift
			;;
		-o | --org)
			a_organization="${2-}"
			shift
			;;
		-p | --pw)
			pw="${2-}"
			shift
			;;
		-s | --state)
			a_state="${2-}"
			shift
			;;
		-t | --unit)
			a_unit="${2-}"
			shift
			;;
		-u | --country)
			a_country="${2-}"
			shift
			;;
		-?*) die "Unknown option: $1" ;;
		*) break ;;
		esac
		shift
	done

	# check required params and arguments
	[[ -z "${a_cname-}" ]] && die "Missing required parameter: cname"
	[[ -z "${config-}" ]] && die "Missing required parameter: config"
	[[ -z "${data_dir-}" ]] && die "Missing required parameter: data-dir"
	[[ -z "${pw-}" ]] && die "Missing required parameter: pw"
	[[ $($openssl version | grep -ci "openssl") == 0 ]] && die "OpenSSL not found on \$PATH. Missing required parameter: openssl"

	return 0
}

parse_params "$@"
setup_colors

# script logic here
config=$(realpath --canonicalize-missing "${config}")
data_dir=$(realpath --canonicalize-missing "${data_dir}")
ra_dir="${data_dir}/${a_cname}"
ra_certs="${ra_dir}/certs"
ra_private="${ra_dir}/private"

[[ ! -f "${config-}" ]] && die "Parameter 'config' does not point to an existing config file"

ca_dirs="certs crl csr newcerts private"
message=$(printf "Setting up root authority folder structure at '%s'\n" "${ra_dir}")
msg "${message}"
for ca_dir in ${ca_dirs}; do
	mkdir -p "${ra_dir}/${ca_dir}"
done

touch "${ra_dir}/index.txt"
$openssl rand -hex 16 >"${ra_dir}/serial"
$openssl rand -hex 16 >"${ra_dir}/crlnumber"

[[ -f "${ra_private}/ra.key.pem" ]] && msg "Private key was already generated, will not overwrite."
if [[ ! -f "${ra_private}/ra.key.pem" ]]; then
	msg "Creating key for the root certificate authority\n"
	$openssl genpkey -algorithm RSA \
		-aes-256-cbc \
		-out "${ra_private}/ra.key.pem" \
		-pass "pass:${pw}" \
		-pkeyopt rsa_keygen_bits:4096
fi

[[ -f "${ra_certs}/ra.cert.pem" && ${force} == 0 ]] && msg "Certificate was already generated, will not overwrite unless '--force' is used."
[[ -f "${ra_certs}/ra.cert.pem" && ${force} == 1 ]] && mv "${ra_certs}/ra.cert.pem" "${ra_certs}/retired-$(date --iso-8601=seconds)-ra.cert.pem"
if [[ -f "${ra_certs}/ra.cert.pem" ]]; then
	if ! $openssl x509 -checkend 0 -noout -in "${ra_certs}/ra.cert.pem"; then
		msg "Certificate is expired or about to, will archive and regenerate."
		endDate="$(date --date="$($openssl x509 -enddate -noout -in "${ra_certs}/ra.cert.pem" | cut -d= -f 2)" --iso-8601=seconds)"
		mv "${ra_certs}/ra.cert.pem" "${ra_certs}/expired-${endDate}-ra.cert.pem"
	fi
fi
if [[ ! -f "${ra_certs}/ra.cert.pem" ]]; then
	message=$(printf "Creating certificate for the root certificate authority using %s\n" "${config}")
	msg "${message}"
	OPENSSL_AUTHORITY_BASE="${data_dir}" OPENSSL_AUTHORITY_COUNTRY="${a_country}" OPENSSL_AUTHORITY_STATE="${a_state}" \
		OPENSSL_AUTHORITY_CITY="${a_city}" OPENSSL_AUTHORITY_ORG="${a_organization}" OPENSSL_AUTHORITY_UNIT="${a_unit}" \
		OPENSSL_AUTHORITY_CNAME="${a_cname}" OPENSSL_AUTHORITY_EMAIL="${a_email}" \
		$openssl req \
		-config "${config}" \
		-days "${expiry}" \
		-extensions v3_ca \
		-key "${ra_private}/ra.key.pem" \
		-sha256 \
		-new \
		-out "${ra_certs}/ra.cert.pem" \
		-passin "pass:${pw}" \
		-x509
fi

[[ ${verbose} == 1 ]] && msg "Verifying the root certificate authority\n"
[[ ${verbose} == 1 ]] && $openssl x509 -noout -text -in "${ra_certs}/ra.cert.pem"
