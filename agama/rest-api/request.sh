#! /usr/bin/bash

URL_PATH=${1:-config}
shift

curl --variable "path=$URL_PATH" "$@" -K curl.conf 
