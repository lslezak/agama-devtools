#! /usr/bin/bash

OPTIONS=()

readarray -t ADDRESSES < <(hostname --all-ip-addresses | tr " " "\n" | grep -v ":")
for ADDR in "${ADDRESSES[@]}"; do
  OPTIONS+=("-addext" "subjectAltName=IP:$ADDR")
done

NAME=`hostname -a`
if ( -n "$NAME"); then
  OPTIONS+=("-addext" "subjectAltName=DNS:$NAME")
fi

# mDNS name
NAME=$(systemctl status avahi-daemon.service | grep "Server startup complete. Host name is" \
  | sed -e "s/^.*Server startup complete. Host name is \(.*\)\. Local.*$/\\1/")
if ( -n "$NAME"); then
  OPTIONS+=("-addext" "subjectAltName=DNS:$NAME")
fi

# create the SSL certificate, forward all CLI arguments to it
openssl req -newkey rsa:2048 -x509 -subj "/CN=localhost" "${OPTIONS[@]}" "$@" -nodes -days 365 -out cert.pem -keyout key.pem
