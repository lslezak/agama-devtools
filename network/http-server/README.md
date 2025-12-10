# Static HTTP server

If you need a static HTTP server for serving a package repository or
an auto installation profile then there are several options.

To run the HTTP server on port 8000 exporting the current directory content run
one of the commands below depending what is available in our system.

## Python

If you have Python3 installed in your system run this command:

```sh
python3 -m http.server 8000
```

## Ruby

If you have Ruby installed in your system run this:

```sh
ruby -run -ehttpd . -p8000
```

*Note: In Ruby 3.0+ you might need to install the Webrick gem with `gem install webrick` command.*

## Darkhttpd

If your system does not include Python or Ruby you can install the
[darkhttpd](https://github.com/emikulic/darkhttpd) server. It is a tiny package
(just ~50kB!) without any other dependencies.

```sh
sudo zypper install darkhttpd
darkhttpd . --port 8000
```
