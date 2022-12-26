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
This script can be used to generate certificate requests to be signed by the intermediate authority.
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-c, --config    OpenSSL intermediate CA configuration file
-d, --data-dir  Location of the intermediate authority
-e, --expiry    After how many days the certificate expires (default 375)
-f, --force     WILL OVERWRITE EXISTING CERTIFICATE
-i, --ips       IPs (Subject Alt Names), a comma separated list of IPs
-l, --openssl   The path to the OpenSSL binary to use
-n, --cname     Common name for the certificate
-m, --client    Request a client certificate
-o, --out-name  Output name of the certificate and key, defaults to 'cname'
-p, --pw        Supply the intermediate authority password
-s, --server    Request a server certificate
-t, --alt-names DNS entries (Subject Alt Names), a comma separated list
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
	alt_ips=''
	alt_names=''
	client=0
	cname=''
	config=''
	data_dir=''
	expiry=375
	force=0
	ia_pw="${SIMPLE_CA_INTERMEDIATE_PASSWORD-}"
	openssl=$(which openssl)
	out_name=''
	server=0
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
		-i | --ips)
			alt_ips="${2-}"
			shift
			;;
		-l | --openssl)
			openssl="${2-}"
			shift
			;;
		-n | --cname)
			cname="${2-}"
			shift
			;;
		-m | --client) client=1 ;;
		-o | --out-name)
			out_name="${2-}"
			shift
			;;
		-p | --pw)
			ia_pw="${2-}"
			shift
			;;
		-s | --server) server=1 ;;
		-t | --alt-names)
			alt_names="${2-}"
			shift
			;;
		-?*) die "Unknown option: $1" ;;
		*) break ;;
		esac
		shift
	done

	# check required params and arguments
	[[ -z "${ia_pw-}" ]] && die "Missing required parameter: pw"
	[[ -z "${config-}" ]] && die "Missing required parameter: config"
	[[ -z "${data_dir-}" ]] && die "Missing required parameter: data-dir"
	[[ -z "${cname-}" ]] && die "Missing required parameter: cname"
	[[ -z "${alt_names-}" ]] && die "Missing required parameter: alt-names"
	[[ ${client} == 0 && ${server} == 0 ]] && die "Missing required parameter: client and/or server"
	[[ $($openssl version | grep -ci "openssl") == 0 ]] && die "OpenSSL not found on \$PATH. Missing required parameter: openssl"

	return 0
}

parse_params "$@"
setup_colors

# https://stackoverflow.com/a/17841619/2920585
function join_by() {
	local IFS="$1"
	shift
	echo "$*"
}

# script logic here

# the slash is required by Windows https://stackoverflow.com/a/54924640/2920585 down at the -subj parameter
cname_windows_fix=""
UNAME=$(command -v uname)
case $("${UNAME}" | tr '[:upper:]' '[:lower:]') in
msys* | cygwin* | mingw*)
	cname_windows_fix="/"
	;;
*)
	cname_windows_fix=""
	;;
esac

config=$(realpath --canonicalize-missing "${config}")
ia_dir=$(realpath --canonicalize-missing "${data_dir}")
ia_certs="${ia_dir}/certs"
ia_csr="${ia_dir}/csr"
ia_private="${ia_dir}/private"
alt_name_array=()
alt_ip_array=()
san=''
extensions=''

[[ ! -f "${config-}" ]] && die "${RED}Parameter 'config' does not point to an existing config file${NOFORMAT}"
[[ ! -d "${ia_dir-}" ]] && die "${RED}Parameter 'data-dir' does not point to an existing location${NOFORMAT}"

if [[ -z "${out_name-}" ]]; then
	out_name="${cname}"
fi

if [[ -n "${alt_names}" ]]; then
	# https://stackoverflow.com/a/45201229/2920585
	IFS=',' read -r -a alt_name_array <<<"$alt_names"
	names=$(join_by , "${alt_name_array[@]/#/DNS:}")
	[[ -n "${names}" ]] && san="${san}${names}"
fi
if [[ -n "${alt_ips}" ]]; then
	# https://stackoverflow.com/a/45201229/2920585
	IFS=',' read -r -a alt_ip_array <<<"$alt_ips"
	ips=$(join_by , "${alt_ip_array[@]/#/IP:}")
	if [[ -n "${ips}" && -n "${san}" ]]; then
		san="${san},${ips}"
	elif [[ -n "${ips}" && -z "${san}" ]]; then
		san="${san}${ips}"
	fi
fi

if [[ ${client} == 1 && ${server} == 1 ]]; then
	extensions="server_client_cert"
else
	[[ ${client} == 1 ]] && extensions='client_cert'
	[[ ${server} == 1 ]] && extensions='server_cert'
fi

[[ -f "${ia_private}/${out_name}.key.pem" ]] && msg "${YELLOW}Private key was already generated, will not overwrite.${NOFORMAT}"
if [[ ! -f "${ia_private}/${out_name}.key.pem" ]]; then
	msg "Creating key for the given cname\n"
	$openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
		-out "${ia_private}/${out_name}.key.pem"
fi

retired_at=$(date --iso-8601=seconds)
[[ -f "${ia_certs}/${out_name}.cert.pem" && ${force} == 0 ]] && msg "Certificate was already generated, will not overwrite unless '--force' is used."
[[ -f "${ia_certs}/${out_name}.cert.pem" && ${force} == 1 ]] && mv "${ia_certs}/${out_name}.cert.pem" "${ia_certs}/retired-${retired_at}-${out_name}.cert.pem"
[[ -f "${ia_certs}/${out_name}.cert-chain.pem" && ${force} == 1 ]] && mv "${ia_certs}/${out_name}.cert-chain.pem" "${ia_certs}/retired-${retired_at}-${out_name}.cert-chain.pem"
if [[ -f "${ia_certs}/${out_name}.cert.pem" ]]; then
	if ! $openssl x509 -checkend 0 -noout -in "${ia_certs}/${out_name}.cert.pem"; then
		msg "${YELLOW}Certificate is expired or about to, will archive and regenerate.${NOFORMAT}"
		endDate="$(date --date="$($openssl x509 -enddate -noout -in "${ia_certs}/${out_name}.cert.pem" | cut -d= -f 2)" --iso-8601)"
		mv "${ia_certs}/${out_name}.cert.pem" "${ia_certs}/expired-${endDate}-${out_name}.cert.pem"
	fi
fi
if [[ ! -f "${ia_certs}/${out_name}.cert.pem" ]]; then
	message=$(printf "Creating certificate signing request for the certificate with cname %s using %s\n" "${out_name}" "${config}")
	msg "${message}"
	OPENSSL_AUTHORITY_BASE="${data_dir}" \
		$openssl req -batch \
		-config "${config}" \
		-addext "subjectAltName=${san}" \
		-key "${ia_private}/${out_name}.key.pem" \
		-sha256 \
		-new \
		-out "${ia_csr}/$(date -I)-${out_name}.csr.pem" \
		-subj "${cname_windows_fix}/CN=${cname}"

	message=$(printf "Creating certificate for the certificate with cname %s using %s\n" "${out_name}" "${config}")
	msg "${message}"
	OPENSSL_AUTHORITY_BASE="${data_dir}" \
		$openssl ca -batch \
		-config "${config}" \
		-days "${expiry}" \
		-extensions "${extensions}" \
		-in "${ia_csr}/$(date -I)-${out_name}.csr.pem" \
		-md sha256 \
		-notext \
		-out "${ia_certs}/${out_name}.cert.pem" \
		-passin "pass:${ia_pw}"
fi
if [[ ! -f "${ia_certs}/${out_name}.cert-chain.pem" ]]; then
	message=$(printf "Creating chain certificate for the certificate with cname %s using %s\n" "${out_name}" "${config}")
	msg "${message}"
	cat "${ia_certs}/${out_name}.cert.pem" "${ia_certs}/ca-chain.cert.pem" >"${ia_certs}/${out_name}.cert-chain.pem"
fi

msg "\n${GREEN}Verifying the root certificate authority${NOFORMAT}"
[[ ${verbose} == 1 ]] && $openssl x509 -noout -text -in "${ia_certs}/${out_name}.cert.pem"
$openssl verify -CAfile "${ia_certs}/ca-chain.cert.pem" "${ia_certs}/${out_name}.cert.pem"
