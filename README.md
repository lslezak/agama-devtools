# Agama development tools and scripts

This repository contains a set of helper scripts and tools useful for developing
the [Agama installer](https://github.com/agama-project/agama).

## Content

### Agama scripts

- [rest-api](./agama/rest-api/) - helper scripts for interacting with the new
  Agama v2 REST API (still in development)
- [live-iso](./live-iso/) - helper script for modifying and rebuilding the Agama
  installation ISO images.

## Network scripts

- [HTTP server](./network/http-server/README.md) - a document describing how to
  run a local static HTTP server
- [HTTPS server](./network/https-server/) - scripts for creating a self-signed
  certificate and running a local static HTTPS server with the generated
  certificate
- [HTTP proxy](./network/proxy/README.md) - document describing how to setup an
  HTTP proxy (both plain HTTP proxy and authenticated HTTP proxy)
- [repository mirror](./network/repo-meta-mirror/) - a simple script for
  mirroring repository metadata (without RPM packages), can be used for testing
  with the HTTPS server with a self-signed certificate or after removing the GPG
  signature as an unsigned repository
