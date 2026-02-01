# Agama ISO image tools

This directory contains a helper script for inspecting and modifying the Agama installation ISO
images.

> [!WARNING]
> *The script builds a new modified ISO file, there is no support for using the modified
> installer! Use at your own risk!*

## `iso-edit-live-root.sh`

A script to modify the root filesystem of an installer ISO and repackage it.
It automates the following process:

1. Extracts `LiveOS/squashfs.img` from the source ISO.
2. Unpacks the `squashfs.img` to access the `LiveOS/rootfs.img` inside.
3. Mounts the `rootfs.img` in read-write mode.
4. Does one of the following:
    - **Interactive Mode (default):** Enters a `chroot` shell, allowing you to modify the
      installer's root filesystem.
    - **Copy Mode (`--copy-root`):** Copies local files/directories into the root filesystem.
    - **Run Mode (`--chroot-run`):** Executes a command within the `chroot` environment.
    - **ISO File Copy (`--copy-iso`):** Copies local files/directories to any path within the ISO
      filesystem.
    - **Grub Editing**: Includes options (`--grub-default`, `--grub-timeout`, `--grub-append`, `--grub-interactive`)
      to modify the `grub.cfg` bootloader configuration. A generic `--extract` option can be used to
      extract any file for inspection.
    - **Combination:** Any combination of rootfs and grub modification options can be used in a
      single command.
5. If any modifications are made, the script repackages the necessary components (`rootfs.img`
   and/or `grub.cfg`) into a new ISO image.
    - With `--rebuild`, the `rootfs.img` is recreated from scratch to produce a clean filesystem.
      This is useful if you delete some big files from the root filesystem or you use some big
      temporary files, for example installing RPM packages.
    - The `--size` option can be used to specify a new size for the rootfs image; this automatically
      implies `--rebuild`.
6. If no changes are to be saved, all temporary files are discarded.

This is useful for debugging or customizing the installer environment. The script requires root
privileges for modifying the root filesystem image. For modifying only the ISO image content
(updating the boot menu, adding packages to the medium, updating kernel/initrd) the root permissions
are not required.

### Usage

```sh
# Interactively make changes in the root image and save them to a new ISO
sudo ./iso-edit-live-root.sh --output /path/to/new.iso /path/to/original.iso

# Non-interactively copy a custom script into the image and build a new ISO
sudo ./iso-edit-live-root.sh --copy-root ./my-script.sh /usr/local/bin/my-script.sh /path/to/original.iso

# Run a command to install a package and build a new ISO
sudo ./iso-edit-live-root.sh --chroot-run "zypper -n in htop" /path/to/original.iso

# Copy a file and then enter an interactive shell to verify
sudo ./iso-edit-live-root.sh --copy-root ./debug.conf /etc/debug.conf --chroot-shell /path/to/original.iso

# Set the default boot menu entry to installation and decrease the default timeout to 3 seconds
./iso-edit-live-root.sh --grub-default 1 --grub-timeout 3 /path/to/original.iso
```

## Use cases

Here are some useful tips and use cases for the `iso-edit-live-root.sh` script.

### Changing default boot menu item

To change the default boot menu item, use the `--grub-default` option. The value is the zero-based
index of the menu entry. For example, to make "Install" action the default use `1` (usually the
Agama default is to boot from disk).

It is also possible to change the timeout for selecting the default menu item.

```sh
./iso-edit-live-root.sh --grub-default 1 --grub-timeout 3 original.iso
```

### Appending boot options

You can append any kernel boot option using `--grub-append`. For example, to disable self-update
in the installer, you can append the `inst.self_update=0` boot option.

```sh
./iso-edit-live-root.sh --grub-append "inst.self_update=0" original.iso
```

See the [Agama boot options](https://agama-project.github.io/docs/user/reference/boot_options)
documentation.

### Replacing installer component

To test a patched version of an installer component, you can replace the needed parts directly.
You can either replace the files from the locally built sources or install an updated RPM package.

```sh
# replace the web frontend from sources
sudo ./iso-edit-live-root.sh --copy-root ./agama/web/dist /usr/share/agama/web_ui original.iso

# replace the web frontend from RPM package
sudo ./iso-edit-live-root.sh --copy-root ./agama-web-ui.noarch.rpm /packages --chroot-run "zypper -n in /packages/agama-web-ui.noarch.rpm" original.iso
```

When using an RPM package it can be installed also as an self-update or driver update (DUD). The
difference is that in that case it would be installed at every boot again and again. See the
description [self-update](#adding-self-update-repository) and [driver
update](#adding-driver-update-dud) sections below for more details.

### Setting default hostname

You can pre-configure the hostname for the running installer using the `hostname` boot option.

```sh
./iso-edit-live-root.sh --grub-append "hostname=my-test-system" original.iso
```

Then you can access the installer remotely using the `https://my-test-system.local` address.

### Adding autoinstallation profile

To perform an unattended installation, you can add an AutoYaST or Agama profile to the ISO and
instruct the installer to use it.

First, place your profile (e.g. `profile.json`) in the root directory of the ISO using `--copy-iso`.
Then, use `--grub-append` to add the `inst.auto` boot parameter, pointing to the file using the
`file://` scheme.

```sh
# the installation medium is mounted at the /run/initramfs/live directory
./iso-edit-live-root.sh --copy-iso ./profile.json /profile.json --grub-append "inst.auto=file:///run/initramfs/live/profile.json" original.iso
```

### Adding SSH key

To make remote access easier for debugging, you can add your SSH public key into the image. This
requires copying your SSH public key to the `/root/.ssh/authorized_keys` file in the root
filesystem.

```sh
# the name of your SSH public key file might be different on your system
sudo ./iso-edit-live-root.sh --copy-root ~/.ssh/id_ed25519.pub /root/.ssh/authorized_keys original.iso
```

### Adding server SSL certificate

To avoid warnings when using an automatically generated SSL certificate, you can include your
predefined certificate in the installer.

```sh
sudo ./iso-edit-live-root.sh --copy-root cert.pem /etc/agama.d/ssl/cert.pem --copy-root key.pem /etc/agama.d/ssl/key.pem original.iso
```

Then you can import the certificate to your web browser or use it with curl:

```sh
curl --cacert cert.pem https://agama.local
```

If you do not have a certificate you can generate a self-signed certificate using the
[create-self-signed-cert.sh](../../network/https-server/create-self-signed-cert.sh) script:

```sh
./create-self-signed-cert.sh --name agama.local
```

or you can generate it manually with this command:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes
```

### Adding local repository

To add a local repository to the ISO image, you need to copy the repository files into the ISO image
and add a boot option pointing to it.

```sh
./iso-edit-live-root.sh --copy-iso repository /repository --grub-append "inst.install_url=dir:/run/initramfs/live/repository" original.iso
```

For testing without installing the packages you can copy only the repository metadata located in the
`/repodata` subdirectory. See the details in the next section.

### Making an offline installation medium

To add a full package repository to the installation medium download the needed repository locally
into the `repository` subdirectory and then run this command:

```sh
./iso-edit-live-root.sh --copy-iso repository /install original.iso
```

You do not have to download all needed packages if you want to test something in the installer
before starting the real installation. For testing you can include only the repository metadata
located in the `/repodata` subdirectory in the repository.

You can use the [repo-meta-mirror](../../network/repo-meta-mirror) script for downloading only the
metadata from a remote repository.

### Adding driver update (DUD)

To provide additional drivers during installation, you can add a Driver Update Disk (DUD) file to
the ISO and point to it with the dud boot parameter.

```sh
# DUD archive created by `mkdud` tool
./iso-edit-live-root.sh --copy-iso ./update.dud /dud/update.dud --grub-append "inst.dud=file:/run/initramfs/live/dud/update.dud" original.iso

# RPM package as DUD
./iso-edit-live-root.sh --copy-iso ./package.rpm /dud/package.rpm --grub-append "inst.dud=file:/run/initramfs/live/dud/package.rpm" original.iso
```

### Adding self-update repository

To update the installer itself before the installation starts, you can add a self-update repository
to the ISO and specify it with the `inst.self_update` boot parameter. Refer to the device using the
device label, that works for both DVD and USB media.

```sh
# get the volume ID which is used as the disk label in booted system
xorriso -indev original.iso -pvd_info 2> /dev/null | grep "Volume Id"

# use hd: URL can refer to a "by-label" device label, the label is the volume ID
./iso-edit-live-root.sh --copy-iso ./updates /updates --grub-append "inst.self_update=hd:/updates?device=/dev/disk/by-label/Install-openSUSE-x86_64" original.iso
```

### Installing debugging tools

If you need to debug the installer, you can add tools like `strace` or `tcpdump`.

```sh
sudo ./iso-edit-live-root.sh --chroot-run "zypper -n in strace tcpdump" original.iso
```

### Enabling serial console

For debugging on virtual machines or physical hardware with a serial port, you can enable a serial
console.

```sh
./iso-edit-live-root.sh --grub-append "console=ttyS0,115200" original.iso
```

### Updating kernel and initrd

It is possible to replace also the Linux kernel and the initrd image.

*Note: You have to use a compatible kernel and initrd otherwise the system will not boot or the
installer will not start properly!*

```sh
./iso-edit-live-root.sh --copy-iso kernel /boot/x86_64/loader/linux --copy-iso initrd /boot/x86_64/loader/initrd  original.iso
```
