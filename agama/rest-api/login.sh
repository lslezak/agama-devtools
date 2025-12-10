#! /usr/bin/bash

DEFAULT_URL="https://agama.local"
URL="$DEFAULT_URL"

usage () {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h             - Print this help"
  echo "  -u <URL>       - Agama URL (default: $DEFAULT_URL)"
  echo "  -p <password>  - Login password (entered interactively if missing)"
  echo "                   Note: this reveals the password in the process list!"
}

# process command line arguments
while getopts ":hp:u:" opt; do
  case ${opt} in
    u)
      URL="${OPTARG}"
      ;;
    p)
      PASSWORD="${OPTARG}"
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "ERROR: Missing argument for option -${OPTARG}"
      echo
      usage
      exit 1
      ;;
    ?)
      echo "ERROR: Invalid option -${OPTARG}"
      echo
      usage
      exit 1
      ;;
  esac
done

if [ -z "$PASSWORD" ]; then
  PASSWORD=$(systemd-ask-password --timeout=0 "Enter login password for $URL: "); 
else
  echo "Logging into $URL...."
fi

TOKEN=$(echo "{\"password\": \"$PASSWORD\"}" \
  | curl -k --silent "$URL/api/auth" --json @- \
  | jq -r .token)

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
  echo "Error: Login failed"
  exit 1
else
  echo "Login successful"
  # user-only file permissions
  umask 0077
  cat << EOF > curl.conf
--insecure
--silent
--fail
-H "Content-Type: application/json"
-H "Authorization: Bearer $TOKEN"
# the "{{path}}" is expanded with "--variable path=value" curl option
--expand-url "$URL/api/v2/{{path}}"
EOF
fi
