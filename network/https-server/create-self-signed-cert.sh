#! /usr/bin/bash

#
# A script which generates a self-signed SSL certificate.
#

# Check if stderr is a terminal and if it supports at least 8 colors
if [[ -t 2 && $(tput colors 2>/dev/null) -ge 8 ]]; then
  RED=$(tput setaf 1)
  NC=$(tput sgr0) # No Color
else
  RED=""
  NC=""
fi

error() {
  echo >&2 "${RED}ERROR: ${*}${NC}"
}

usage() {
  echo "Usage: $0 [options] [openssl_options]"
  echo
  echo "Creates a self-signed SSL certificate (cert.pem) and a private key (key.pem)."
  echo "It automatically adds local IP addresses and hostnames to the certificate."
  echo
  echo "Options:"
  echo "  --help, -h          Show this help message and exit."
  echo "  --ip <ip_address>   Add an IP address to the certificate's Subject Alternative Name."
  echo "                      Can be used multiple times."
  echo "  --name <dns_name>   Add a DNS name to the certificate's Subject Alternative Name."
  echo "                      Can be used multiple times."
  echo
  echo "Any other arguments are passed directly to the 'openssl req' command."
}

OPTIONS=()
OPENSSL_ARGS=()

# Run autodetection only when no arguments are passed
if [[ $# -eq 0 ]]; then
  readarray -t ADDRESSES < <(hostname --all-ip-addresses | tr " " "\n" | grep -v ":")
  for ADDR in "${ADDRESSES[@]}"; do
    OPTIONS+=("-addext" "subjectAltName=IP:$ADDR")
  done

  NAME=$(hostname -a)
  if [[ -n "$NAME" ]]; then
    OPTIONS+=("-addext" "subjectAltName=DNS:$NAME")
  fi

  # mDNS name
  NAME=$(systemctl status avahi-daemon.service | grep "Server startup complete. Host name is" |
    sed -e "s/^.*Server startup complete. Host name is \(.*\)\. Local.*$/\\1/")
  if [[ -n "$NAME" ]]; then
    OPTIONS+=("-addext" "subjectAltName=DNS:$NAME")
  fi
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --ip)
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "Option --ip requires an IP address."
      exit 1
    fi
    OPTIONS+=("-addext" "subjectAltName=IP:$2")
    shift 2
    ;;
  --name)
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "Option --name requires a DNS name."
      exit 1
    fi
    OPTIONS+=("-addext" "subjectAltName=DNS:$2")
    shift 2
    ;;
  *)
    OPENSSL_ARGS+=("$1")
    shift
    ;;
  esac
done

# create the SSL certificate, forward all CLI arguments to it
openssl req -newkey rsa:2048 -x509 -subj "/CN=localhost" -nodes -days 365 "${OPTIONS[@]}" "${OPENSSL_ARGS[@]}" -out cert.pem -keyout key.pem
