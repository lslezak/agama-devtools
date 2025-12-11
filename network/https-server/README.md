# Static HTTPS server with a self-signed SSL certificate

If you need a testing static HTTPS server which uses a self-signed SSL
certificate you can use the scripts in this directory.

## Self-signed SSL certificate

First run the [create-self-signed-cert.sh](./create-self-signed-cert.sh) script
which creates a self-signed SSL certificate in file `cert.pem` and its private
key in file `key.pem`.

Alternatively you can use the `/usr/sbin/check-create-certificate` script from
the "check-create-certificate" RPM package.

## HTTPS server

There are two scripts which implement a static HTTPS server. Both scripts expect
the SSL certificate in the `cert.pem` file and its private key in the `key.pem`
file and both scripts use the port 4433.

- [https-server.py](./https-server.py) - a Python script
- [https-server.rb](./https-server.rb) - a Ruby script

After starting a script you can connect to https://localhost:4433. Expect an
error reported by browser or download tools because of the self signed
certificate.

When testing with curl you need to either disable the SSL checks with the
`--insecure` option or specify the SSL certificate to use with the `--cacert
cert.pem` option.

## Debugging

Some SSL debugging hints are described in [this YaST
documentation](https://github.com/yast/yast-registration/wiki/OpenSSL-Debugging-Hints).
