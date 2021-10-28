#!/usr/bin/env bash

# script-template.sh https://gist.github.com/m-radzikowski/53e0b39e9a59a1518990e76c2bff8038 by Maciej Radzikowski
# MIT License https://gist.github.com/m-radzikowski/d925ac457478db14c2146deadd0020cd
# https://betterdev.blog/minimal-safe-bash-script-template/

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f]
This script can be used to generate an SSH keypair to be used as SSH certificate authority.
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-c, --comment   OpenSSH Key comment
-d, --data-dir  Target directory where to store the CA
-f, --force     WILL OVERWRITE EXISTING CERTIFICATE
-n, --name      Name of the CA
-p, --pw        OpenSSH Key passphrase
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
	comment=''
	data_dir=''
	force=0
	name=''
	pw="${SIMPLE_CA_SSH_PASSWORD-}"

	while :; do
		case "${1-}" in
		-h | --help) usage ;;
		-v | --verbose) set -x ;;
		--no-color) NO_COLOR=1 ;;
		-c | --comment)
			comment="${2-}"
			shift
			;;
		-d | --data-dir)
			data_dir="${2-}"
			shift
			;;
		-f | --force) force=1 ;;
		-n | --name)
			name="${2-}"
			shift
			;;
		-p | --pw)
			pw="${2-}"
			shift
			;;
		-?*) die "Unknown option: $1" ;;
		*) break ;;
		esac
		shift
	done

	# check required params and arguments
	[[ -z "${data_dir-}" ]] && die "Missing required parameter: data-dir"
	[[ -z "${name-}" ]] && die "Missing required parameter: name"
	[[ -z "${pw-}" ]] && die "Missing required parameter: pw"

	return 0
}

parse_params "$@"
setup_colors

# script logic here
data_dir=$(realpath --canonicalize-missing "${data_dir}/${name}")
ca="${data_dir}/ca"

if [[ ! -d "${data_dir}" ]]; then
	message=$(printf "Ensuring that target directory '%s' exists.\n" "${data_dir}")
	msg "${message}"
	mkdir -p "${data_dir}"
fi

[[ -f "${ca}" && ${force} == 0 ]] && msg "Certificate was already generated, will not overwrite unless '--force' is used."
if [[ ! -f "${ca}" || ${force} == 1 ]]; then
	message=$(printf "Generating OpenSSH CA Key Pair at %s\n" "${data_dir}")
	msg "${message}"
	ssh-keygen -f "${data_dir}/ca" \
		-t rsa \
		-b 4096 \
		-N "${pw}" \
		-C "${comment}"
fi
