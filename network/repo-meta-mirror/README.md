# Repository metadata mirror

This directory contains a simple script for mirroring repository metadata
without mirroring the RPM packages. It can be used for testing with the HTTPS
server with a self-signed certificate or after removing the GPG signature as an
unsigned repository without mirroring a complete repository.

To mirror a repository simply run the `./mirror [URL]` command with the
repository URL as the argument. If no URL is specified it by default downloads
the openSUSE Tumbleweed OSS repository data.

The metadata files are downloaded into the `repodata` subdirectory, if you want
to export the repository you need to share the `repodata` parent directory.
