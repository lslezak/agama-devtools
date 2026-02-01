# Static HTTPS server with a self-signed SSL certificate

If you need a testing static HTTPS server which uses a self-signed SSL
certificate you can use the scripts in this directory.

## Self-signed SSL certificate

First run the [create-self-signed-cert.sh](./create-self-signed-cert.sh) script
which creates a self-signed SSL certificate in file `cert.pem` and its private
key in file `key.pem`.

The script automatically adds all local IP addresses and host names to the
certificate from the current machine. If you want to use different values use
the `--ip <ip_address>` and `--name <dns_name>` script options.

Alternatively you can use the `/usr/sbin/check-create-certificate` script from
the "check-create-certificate" RPM package or generate the certificate manually:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes
```

## HTTPS server

There are two scripts which implement a static HTTPS server. Both scripts expect
the SSL certificate in the `cert.pem` file and its private key in the `key.pem`
file and both scripts use the port 4433.

- [https-server.py](./https-server.py) - a Python script
- [https-server.rb](./https-server.rb) - a Ruby script

After starting a script you can connect to https://localhost:4433. Expect an
error reported by browser or download tools because of the self signed
certificate.

If you just need to test the SSL connection itself you can also run this
command:

```sh
openssl s_server -key key.pem -cert cert.pem -accept 4433 -www
```

This will run a web server which returns an HTML page with the SSL connection
details.

When testing with curl you need to either disable the SSL checks with the
`--insecure` option or specify the SSL certificate to use with the `--cacert
cert.pem` option.

## Debugging

Some SSL debugging hints are described in [this YaST
documentation](https://github.com/yast/yast-registration/wiki/OpenSSL-Debugging-Hints).
