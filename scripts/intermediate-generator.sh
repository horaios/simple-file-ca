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
This script can be used to generate an intermediate certificate authority.
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-c, --config    OpenSSL intermediate CA configuration file
-d, --data-dir  Target directory where to store the CA
-e, --expiry    After how many days the certificate expires (default 3650)
-f, --force     WILL OVERWRITE EXISTING CERTIFICATE
-g, --ra-config OpenSSL root CA configuration file
-i, --city      City of the certificate authority
-l, --openssl   The path to the OpenSSL binary to use
-m, --email     E-Mail of the certificate authority
-n, --cname     Common name for the certificate authority
-o, --org       Organization of the certificate authority
-p, --pw        Supply the intermediate authority password
-r, --ra-dir    Location of the root authority
-s, --state     State/Province of the certificate authority
-t, --unit      Organizational Unit of the certificate authority
-u, --country   Country of the certificate authority
-w, --ra-pw     Supply the root authority password
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
	expiry=3650
	force=0
	ia_pw="${SIMPLE_CA_INTERMEDIATE_PASSWORD-}"
	openssl=$(which openssl)
	ra_config=''
	ra_dir=''
	ra_pw="${SIMPLE_CA_ROOT_PASSWORD-}"
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
		-g | --ra-config)
			ra_config="${2-}"
			shift
			;;
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
			ia_pw="${2-}"
			shift
			;;
		-r | --ra-dir)
			ra_dir="${2-}"
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
		-w | --ra-pw)
			ra_pw="${2-}"
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
	[[ -z "${ia_pw-}" ]] && die "Missing required parameter: pw"
	[[ -z "${ra_config-}" ]] && die "Missing required parameter: ra-config"
	[[ -z "${ra_dir-}" ]] && die "Missing required parameter: ra-csr"
	[[ -z "${ra_pw-}" ]] && die "Missing required parameter: ra-pw"
	[[ $($openssl version | grep -ci "openssl") == 0 ]] && die "OpenSSL not found on \$PATH. Missing required parameter: openssl"

	return 0
}

parse_params "$@"
setup_colors

# script logic here
config=$(realpath --canonicalize-missing "${config}")
data_dir=$(realpath --canonicalize-missing "${data_dir}")
ia_dir="${data_dir}/${a_cname}"
ia_certs="${ia_dir}/certs"
ia_private="${ia_dir}/private"

ra_config=$(realpath --canonicalize-missing "${ra_config}")
ra_dir=$(realpath --canonicalize-missing "${ra_dir}")
ra_cert="${ra_dir}/certs/ra.cert.pem"
ra_csr="${ra_dir}/csr"

[[ ! -f "${config-}" ]] && die "${RED}Parameter 'config' does not point to an existing config file${NOFORMAT}"
[[ ! -f "${ra_config-}" ]] && die "${RED}Parameter 'ra-config' does not point to an existing config file${NOFORMAT}"
[[ ! -d "${ra_dir-}" ]] && die "${RED}Parameter 'ra-dir' does not point to an existing location${NOFORMAT}"

ca_dirs="certs crl csr newcerts private"
message=$(printf "Setting up intermediate authority folder structure at '%s'\n" "${ia_dir}")
msg "${message}"
for ca_dir in ${ca_dirs}; do
	mkdir -p "${ia_dir}/${ca_dir}"
done

touch "${ia_dir}/index.txt"
$openssl rand -hex 16 >"${ia_dir}/serial"
$openssl rand -hex 16 >"${ia_dir}/crlnumber"

[[ -f "${ia_private}/ia.key.pem" ]] && msg "${YELLOW}Private key was already generated, will not overwrite.${NOFORMAT}"
if [[ ! -f "${ia_private}/ia.key.pem" ]]; then
	msg "Creating key for the intermediate certificate authority\n"
	$openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
		-out "${ia_private}/ia.key.pem" \
		-aes-256-cbc -pass "pass:${ia_pw}"
fi

[[ -f "${ia_certs}/ia.cert.pem" && ${force} == 0 ]] && msg "${YELLOW}Certificate was already generated, will not overwrite unless '--force' is used.${NOFORMAT}"
[[ -f "${ia_certs}/ia.cert.pem" && ${force} == 1 ]] && mv "${ia_certs}/ia.cert.pem" "${ia_certs}/retired-$(date --iso-8601=seconds)-ia.cert.pem"
if [[ -f "${ia_certs}/ia.cert.pem" ]]; then
	if ! $openssl x509 -checkend 0 -noout -in "${ia_certs}/ia.cert.pem"; then
		msg "${YELLOW}Certificate is expired or about to, will archive and regenerate.${NOFORMAT}"
		endDate="$(date --date="$($openssl x509 -enddate -noout -in "${ia_certs}/ia.cert.pem" | cut -d= -f 2)" --iso-8601)"
		mv "${ia_certs}/ia.cert.pem" "${ia_certs}/expired-${endDate}-ia.cert.pem"
	fi
fi
if [[ ! -f "${ia_certs}/ia.cert.pem" ]]; then
	message=$(printf "Creating certificate signing request for the intermediate certificate authority using %s\n" "${config}")
	msg "${message}"
	OPENSSL_AUTHORITY_BASE="${data_dir}" OPENSSL_AUTHORITY_COUNTRY="${a_country}" OPENSSL_AUTHORITY_STATE="${a_state}" \
		OPENSSL_AUTHORITY_CITY="${a_city}" OPENSSL_AUTHORITY_ORG="${a_organization}" OPENSSL_AUTHORITY_UNIT="${a_unit}" \
		OPENSSL_AUTHORITY_CNAME="${a_cname}" OPENSSL_AUTHORITY_EMAIL="${a_email}" \
		$openssl req -batch \
		-config "${config}" \
		-key "${ia_private}/ia.key.pem" \
		-sha256 \
		-new \
		-out "${ra_csr}/$(date -I)-${a_cname}.csr.pem" \
		-passin "pass:${ia_pw}"

	message=$(printf "Creating certificate for the intermediate certificate authority using %s\n" "${ra_config}")
	msg "${message}"
	OPENSSL_AUTHORITY_BASE="${ra_dir}" OPENSSL_AUTHORITY_COUNTRY="${a_country}" OPENSSL_AUTHORITY_STATE="${a_state}" \
		OPENSSL_AUTHORITY_CITY="${a_city}" OPENSSL_AUTHORITY_ORG="${a_organization}" OPENSSL_AUTHORITY_UNIT="${a_unit}" \
		OPENSSL_AUTHORITY_CNAME="${a_cname}" OPENSSL_AUTHORITY_EMAIL="${a_email}" \
		$openssl ca -batch \
		-config "${ra_config}" \
		-days "${expiry}" \
		-extensions v3_intermediate_ca \
		-in "${ra_csr}/$(date -I)-${a_cname}.csr.pem" \
		-md sha256 \
		-notext \
		-out "${ia_certs}/ia.cert.pem" \
		-passin "pass:${ra_pw}"
fi

msg "\n${GREEN}Verifying the root certificate authority${NOFORMAT}"
[[ ${verbose} == 1 ]] && $openssl x509 -noout -text -in "${ia_certs}/ia.cert.pem"
$openssl verify -CAfile "${ra_cert}" "${ia_certs}/ia.cert.pem"

msg "\n${GREEN}Copying the root certificate authority\n${NOFORMAT}"
cp "${ra_cert}" "${ia_certs}/ca.cert.pem"

msg "${GREEN}Creating the certificate authority chain\n${NOFORMAT}"
cat "${ia_certs}/ia.cert.pem" "${ra_cert}" >"${ia_certs}/ca-chain.cert.pem"
