# Interacting with Agama's API

This directory includes few small scripts that you can use to interact with
the Agama REST API from shell.

## Logging in

Run the [login.sh](./login.sh) script to log into an Agama system.

By default it uses the Agama instance running at https://agama.local URL but
you can change the server URL with the `-u` option.

The password can be provided on the command line via the `-p` option, but be
careful, this reveals the password in the process list! If the password is not
specified on the command line the script asks for it interactively. This
is recommended to avoid leaking the password in the process list.

The login script creates the `curl.conf` file which contains the login token,
the used Agama URL and some more curl options which are used later when sending
requests.

## Sending requests

For sending the API requests use the [requests.sh](./request.sh) script. The
first parameter is the API endpoint name (without the `/api/v2` prefix). The
remaining parameters are just passed to the curl call unmodified so you can pass
whatever curl option you need.

### Examples

Here are few request examples:

```sh
# reset the configuration
./request.sh config -X PUT -d '{}'

# partially update the configuration (select SLES with the GNOME pattern)
./request.sh config -X PATCH -d '{"update": {"product": {"id": "SLES"}, "software": {"patterns": ["gnome"] }}}'

# show current configuration
./request.sh config | jq

# show the proposal
./request.sh proposal | jq

# show the current issues
./request.sh issues | jq
```
