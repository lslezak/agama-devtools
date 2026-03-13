# Image Download

This directory contains scripts for downloading Agama ISO images.

You can run the scripts directly or you can installe them using the `Makefile`.
Run `make install` as regular user to install them in into `~/bin` directory. If
started as `root` user (directly or via `sudo`) the scripts are installed into
the  `/usr/local/bin` directory.

## `agama-download-image`

This script downloads specific Agama ISO images. It automatically handles:

- Listing the available images
- Finding the latest version for development and testing images
- Verifying SHA256 checksums
- Verifying GPG signatures

**Usage:**

```bash
agama-download-image [options] [image-id]
```

**Options:**

- `--arch <arch>`: Specify the architecture (default: system architecture).
  Supported: `x86_64`, `aarch64`, `s390x`, `ppc64le`.

- `[image-id]`: Name of the image to download. Run the script without
  arguments to see the list of available image IDs.

## `agama-image-dirs`

This script sets up a directory structure for storing different Agama images. It
creates a directory for each product/version and generates convenience wrapper
scripts (`download-online`, `download-offline`) inside them. To download an
image just run the download script inside.

**Usage:**

```bash
agama-image-dirs [target-directory]
```

**Options:**

- `[target-directory]`: Where to create the directory structure. If not
  specified it uses the `./agama-images/` path.
