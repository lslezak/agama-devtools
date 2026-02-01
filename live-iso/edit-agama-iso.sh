#!/bin/bash
#
# A script for modifying the Agama installation ISO images.
#
# Dependencies: xorriso, unsquashfs, mksquashfs, root privileges (for mount)
#

set -e          # Exit immediately if a command exits with a non-zero status.
set -u          # Treat unset variables as an error when substituting.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Colors and Helpers ---
# Check if stderr is a terminal and if it supports at least 8 colors
if [[ -t 2 && $(tput colors 2>/dev/null) -ge 8 ]]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  NC=$(tput sgr0) # No Color
else
  RED=""
  GREEN=""
  YELLOW=""
  NC=""
fi

error() {
  echo >&2 "${RED}ERROR: ${*}${NC}"
}

warning() {
  echo >&2 "${YELLOW}WARNING: ${*}${NC}"
}

info() {
  echo "${*}"
}

success() {
  echo "${GREEN}${*}${NC}"
}

# --- Configuration ---
SQUASHFS_IMG_PATH_IN_ISO="/LiveOS/squashfs.img"
ROOTFS_IMG_PATH_IN_SQUASHFS="/LiveOS/rootfs.img"
GRUB_CFG_PATH_IN_ISO="/boot/grub2/grub.cfg"

# Use the EDITOR environment variable, or default to 'vim'.
EDITOR="${EDITOR:-vim}"

# --- Functions ---

usage() {
  echo "Usage: $0 [options] <iso_file>"
	echo ""
  echo "Allows modifying the Agama installation ISO images."
  echo ""
  echo "Options:"
  echo "  -h, --help           Show this help message and exit."
  echo "  --extract <iso_path> <local_path>  Extract a file from the ISO and exit."
  echo "  --copy-iso <local_path> <iso_path>   Copy a local file/dir to the ISO. Can be used multiple times."
  echo "  --copy-root <local_path> <root_path> Copy local file/dir to the rootfs. Can be used multiple times."
  echo "  --chroot-run <command>               Execute a command in the chroot after copying files."
  echo "                                       The script will repackage on success."
  echo "  --chroot-shell                       Enter an interactive shell. Useful with --copy-root to inspect"
  echo "                                       changes before repackaging. Implied if no other action is specified."
  echo "  --rebuild           Rebuild the rootfs ext4 image from scratch to remove deleted data."
  echo "  --size <size>       Create a new rootfs image of <size> (e.g., 4G)."
  echo "                      This option implies --rebuild."
  echo "  --grub-default <N>    Set the default grub menu entry to N (must be a number)."
  echo "  --grub-timeout <N>    Set the grub menu timeout to N seconds."
  echo "  --grub-append <opts> Append kernel options to 'Install' menu entries in grub.cfg."
  echo "  --grub-interactive  Interactively edit grub.cfg using editor."
  echo "  --output <file>     Specify the output ISO file name."
  echo "                      Default: input file with '*-edited.iso' suffix."
  echo "Requires root privileges to perform mount operations."
  exit 1
}

setup_chroot_env() {
  info "Preparing chroot environment..."
  # Copy resolv.conf for network access inside chroot
  if [[ -f /etc/resolv.conf ]]; then
    info "Copying host's /etc/resolv.conf into chroot for network access."
    local resolv_conf_in_chroot="${ROOTFS_MOUNT_POINT}/etc/resolv.conf"

    if [[ -e "${resolv_conf_in_chroot}" ]]; then
      mv "${resolv_conf_in_chroot}" "${resolv_conf_in_chroot}.orig"
    fi

    cp /etc/resolv.conf "${resolv_conf_in_chroot}"
    COPIED_RESOLV_CONF_CHECKSUM=$(sha256sum "${resolv_conf_in_chroot}" | awk '{print $1}')
  fi

  mount --bind /proc "${ROOTFS_MOUNT_POINT}/proc"
  mount --bind /sys "${ROOTFS_MOUNT_POINT}/sys"
  mount --bind /dev "${ROOTFS_MOUNT_POINT}/dev"
  mount -t devpts none "${ROOTFS_MOUNT_POINT}/dev/pts"
}

teardown_chroot_env() {
  info "Unmounting chroot-specific filesystems..."
  umount "${ROOTFS_MOUNT_POINT}/dev/pts"
  umount "${ROOTFS_MOUNT_POINT}/dev"
  umount "${ROOTFS_MOUNT_POINT}/sys"
  umount "${ROOTFS_MOUNT_POINT}/proc"

  # Clean up resolv.conf
  if [[ -n "$COPIED_RESOLV_CONF_CHECKSUM" ]]; then
    local resolv_conf_in_chroot="${ROOTFS_MOUNT_POINT}/etc/resolv.conf"
    local current_checksum
    current_checksum=$(sha256sum "${resolv_conf_in_chroot}" | awk '{print $1}')

    if [[ "$current_checksum" == "$COPIED_RESOLV_CONF_CHECKSUM" ]]; then
      rm "${resolv_conf_in_chroot}"
      if [[ -e "${resolv_conf_in_chroot}.orig" ]]; then
        mv "${resolv_conf_in_chroot}.orig" "${resolv_conf_in_chroot}"
      fi
    else
      info "/etc/resolv.conf was modified in chroot, keeping the changes."
      if [[ -e "${resolv_conf_in_chroot}.orig" ]]; then
        rm "${resolv_conf_in_chroot}.orig"
      fi
    fi
  fi
}

cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "${WORK_DIR}" ]]; then
    if [[ -n "${ORIG_ROOTFS_MOUNT_POINT:-}" ]] && mountpoint -q "${ORIG_ROOTFS_MOUNT_POINT}"; then umount "${ORIG_ROOTFS_MOUNT_POINT}"; fi

    if [ -n "$ROOTFS_MOUNT_POINT" ]; then
      # Unmount in reverse order of mounting
      if mountpoint -q "${ROOTFS_MOUNT_POINT}/dev/pts"; then umount "${ROOTFS_MOUNT_POINT}/dev/pts"; fi
      if mountpoint -q "${ROOTFS_MOUNT_POINT}/dev"; then umount "${ROOTFS_MOUNT_POINT}/dev"; fi
      if mountpoint -q "${ROOTFS_MOUNT_POINT}/sys"; then umount "${ROOTFS_MOUNT_POINT}/sys"; fi
      if mountpoint -q "${ROOTFS_MOUNT_POINT}/proc"; then umount "${ROOTFS_MOUNT_POINT}/proc"; fi
      if mountpoint -q "${ROOTFS_MOUNT_POINT}"; then
        umount "${ROOTFS_MOUNT_POINT}"
      fi
    fi
    rm -rf "${WORK_DIR}"
  fi
}

# --- Main Script ---

if [[ $# -eq 0 ]]; then
  usage
fi

OUTPUT_ISO=""
COPY_OPS=()
RUN_COMMAND=""
INTERACTIVE_SHELL=false
REBUILD_ROOTFS=false
ORIG_ROOTFS_MOUNT_POINT=""
NEW_ROOTFS_SIZE=""
COPIED_RESOLV_CONF_CHECKSUM=""
GRUB_DEFAULT_ITEM=""
GRUB_TIMEOUT=""
GRUB_APPEND_OPTS=""
GRUB_UPDATE_FILE=""
GRUB_INTERACTIVE=false
COPY_ISO_OPS=()
EXTRACT_ISO_PATH=""
EXTRACT_LOCAL_PATH=""
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    ;;
  --output)
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--output requires a file path."
      usage
    fi
    OUTPUT_ISO="$2"
    shift 2
    ;;
  --copy-root)
    if [[ -z "${2:-}" || "$2" =~ ^- || -z "${3:-}" || "$3" =~ ^- ]]; then
      error "--copy-root requires a <local_path> and an <image_path>."
      usage
    fi
    COPY_OPS+=("$2") # local_path
    COPY_OPS+=("$3") # image_path

    if [[ ! "$3" =~ ^/ ]]; then
      error "Image path for --copy-root must be an absolute path: $3"
      exit 1
    fi

    shift 3
    ;;
  --chroot-run)
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--chroot-run requires a command string."
      usage
    fi
    RUN_COMMAND="$2"
    shift 2
    ;;
  --chroot-shell)
    INTERACTIVE_SHELL=true
    shift
    ;;
  --rebuild)
    REBUILD_ROOTFS=true
    shift
    ;;
  --size)
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--size requires a size argument (e.g., 4G)."
      usage
    fi
    NEW_ROOTFS_SIZE="$2"
    REBUILD_ROOTFS=true
    shift 2
    ;;
  --grub-default)
    if [[ -z "${2:-}" || "$2" =~ ^- || ! "$2" =~ ^[0-9]+$ ]]; then
      error "--grub-default requires a non-negative number."
      usage
    fi
    GRUB_DEFAULT_ITEM="$2"
    shift 2
    ;;
  --grub-timeout)
    if [[ -z "${2:-}" || "$2" =~ ^- || ! "$2" =~ ^[0-9]+$ ]]; then
      error "--grub-timeout requires a non-negative number."
      usage
    fi
    GRUB_TIMEOUT="$2"
    shift 2
    ;;
  --grub-append)
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--grub-append requires an options string."
      usage
    fi
    GRUB_APPEND_OPTS="$2"
    shift 2
    ;;
  --copy-iso)
    if [[ -z "${2:-}" || "$2" =~ ^- || -z "${3:-}" || "$3" =~ ^- ]]; then
      error "--copy-iso requires a <local_path> and an <iso_path>."
      usage
    fi
    local_path="$2"
    iso_path="$3"
    if [[ "$iso_path" == "$GRUB_CFG_PATH_IN_ISO" ]]; then
      if [[ -n "$GRUB_UPDATE_FILE" ]]; then
        error "Cannot specify multiple sources for ${GRUB_CFG_PATH_IN_ISO}."
        exit 1
      fi
      GRUB_UPDATE_FILE="$local_path"
    else
      COPY_ISO_OPS+=("$local_path")
      COPY_ISO_OPS+=("$iso_path")
    fi
    shift 3
    ;;
  --extract)
    if [[ -z "${2:-}" || "$2" =~ ^- || -z "${3:-}" || "$3" =~ ^- ]]; then
      error "--extract requires an <iso_path> and a <local_path>."
      usage
    fi
    EXTRACT_ISO_PATH="$2"
    EXTRACT_LOCAL_PATH="$3"
    shift 3
    ;;
  --grub-interactive)
    if ! command -v "${EDITOR}" &>/dev/null; then
      error "Editor '${EDITOR}' not found."
      exit 1
    fi
    GRUB_INTERACTIVE=true
    shift
    ;;
  -*)
    error "Unknown option: $1"
    usage
    ;;
  *)
    POSITIONAL_ARGS+=("$1")
    shift
    ;;
  esac
done

if [[ "${#POSITIONAL_ARGS[@]}" -ne 1 ]]; then
  error "Exactly one ISO file must be specified."
  usage
fi

ISO_FILE="${POSITIONAL_ARGS[0]}"
if [[ ! -f "$ISO_FILE" ]]; then
  error "ISO file not found $ISO_FILE"
  exit 1
fi

# Handle extract as an exclusive action
if [[ -n "$EXTRACT_ISO_PATH" ]]; then
  if [[ ${#COPY_OPS[@]} -gt 0 || -n "$RUN_COMMAND" || "$INTERACTIVE_SHELL" == "true" || -n "$GRUB_APPEND_OPTS" || -n "$GRUB_UPDATE_FILE" || "$GRUB_INTERACTIVE" == "true" || "$REBUILD_ROOTFS" == "true" || -n "$GRUB_DEFAULT_ITEM" || ${#COPY_ISO_OPS[@]} -gt 0 ]]; then
    error "--extract cannot be combined with other modification options."
    exit 1
  fi
  info "Extracting ${EXTRACT_ISO_PATH} to ${EXTRACT_LOCAL_PATH}..."
  if ! xorriso -osirrox on -indev "${ISO_FILE}" -extract "${EXTRACT_ISO_PATH}" "${EXTRACT_LOCAL_PATH}" &>/dev/null; then
    error "Failed to extract ${EXTRACT_ISO_PATH}. Please check if the path is correct for your ISO file."
    exit 1
  fi
  success "Successfully extracted ${EXTRACT_ISO_PATH} to ${EXTRACT_LOCAL_PATH}"
  exit 0
fi

DEFAULT_ACTION=false
if [[ ${#COPY_OPS[@]} -eq 0 && -z "$RUN_COMMAND" && "$INTERACTIVE_SHELL" == "false" && -z "$GRUB_APPEND_OPTS" && -z "$GRUB_UPDATE_FILE" && "$GRUB_INTERACTIVE" == "false" && -z "$GRUB_DEFAULT_ITEM" && -z "$GRUB_TIMEOUT" && ${#COPY_ISO_OPS[@]} -eq 0 ]]; then
  DEFAULT_ACTION=true
fi

DO_ROOTFS_ACTIONS=false
if [[ ${#COPY_OPS[@]} -gt 0 || -n "$RUN_COMMAND" || "$INTERACTIVE_SHELL" == "true" || "$DEFAULT_ACTION" == "true" || "$REBUILD_ROOTFS" == "true" ]]; then
  DO_ROOTFS_ACTIONS=true
fi

if [[ "$DO_ROOTFS_ACTIONS" == "true" ]]; then
  if [[ $EUID -ne 0 ]]; then
    error "Root privileges are required to modify the root filesystem."
    error "Please run again using 'sudo'."
    exit 1
  fi
fi

if ! command -v xorriso &>/dev/null; then
  error "The 'xorriso' tool is not installed. Please install it to continue."
  exit 1
fi

NEW_ISO_FILENAME="${OUTPUT_ISO:-${ISO_FILE%.iso}-edited.iso}"
if [[ -e "$NEW_ISO_FILENAME" ]]; then
  error "Output file ${NEW_ISO_FILENAME} already exists. Remove it or use --output."
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap cleanup EXIT SIGINT SIGTERM

ROOTFS_MOUNT_POINT="${WORK_DIR}/rootfs_mount"

if [[ "$DO_ROOTFS_ACTIONS" == "true" ]]; then
  if ! command -v unsquashfs &>/dev/null; then
    error "The 'unsquashfs' tool is not installed. Please install it to continue (e.g., install the 'squashfs-tools' package)."
    exit 1
  fi

  if ! command -v mksquashfs &>/dev/null; then
    error "The 'mksquashfs' tool is not installed. Please install it to continue (e.g., install the 'squashfs-tools' package)."
    exit 1
  fi

  if [[ "$REBUILD_ROOTFS" == "true" ]]; then
    if ! command -v mkfs.ext4 &>/dev/null; then
      error "The 'mkfs.ext4' tool is not installed. Please install it to continue (e.g., 'e2fsprogs' package)."
      exit 1
    fi
    if ! command -v truncate &>/dev/null; then
      error "The 'truncate' tool is not installed. Please install it to continue (e.g., 'coreutils' package)."
      exit 1
    fi
  fi

  EXTRACTED_SQUASHFS_IMG="${WORK_DIR}/squashfs.img"
  SQUASHFS_CONTENT_DIR="${WORK_DIR}/squashfs_content"

  mkdir -p "${SQUASHFS_CONTENT_DIR}" "${ROOTFS_MOUNT_POINT}"

  info "Extracting ${SQUASHFS_IMG_PATH_IN_ISO} from ${ISO_FILE}..."
  xorriso -osirrox on -indev "${ISO_FILE}" -extract "${SQUASHFS_IMG_PATH_IN_ISO}" "${EXTRACTED_SQUASHFS_IMG}" &>/dev/null

  info "Unsquashing ${EXTRACTED_SQUASHFS_IMG} image..."
  unsquashfs -d "${SQUASHFS_CONTENT_DIR}" "${EXTRACTED_SQUASHFS_IMG}" &>/dev/null

  ROOTFS_IMG_PATH="${SQUASHFS_CONTENT_DIR}${ROOTFS_IMG_PATH_IN_SQUASHFS}"
  if [[ ! -f "$ROOTFS_IMG_PATH" ]]; then
    error "${ROOTFS_IMG_PATH} not found inside the squashfs image."
    exit 1
  fi

  if [[ "$REBUILD_ROOTFS" == "true" ]]; then
    info "Rebuilding rootfs image..."
    ORIG_ROOTFS_MOUNT_POINT="${WORK_DIR}/orig_rootfs_mount"
    mkdir -p "${ORIG_ROOTFS_MOUNT_POINT}"

    info "Mounting original rootfs image (read-only)..."
    mount -o loop,ro "${ROOTFS_IMG_PATH}" "${ORIG_ROOTFS_MOUNT_POINT}"

    image_size=""
    if [[ -n "$NEW_ROOTFS_SIZE" ]]; then
      image_size="$NEW_ROOTFS_SIZE"
      size_desc="$NEW_ROOTFS_SIZE"
    else
      image_size=$(stat -c %s "${ROOTFS_IMG_PATH}")
      size_desc="${image_size} bytes (original size)"
    fi
    new_rootfs_img="${WORK_DIR}/new_rootfs.img"

    info "Creating new ext4 image of size ${size_desc}..."
    truncate -s "${image_size}" "${new_rootfs_img}"
    mkfs.ext4 -F "${new_rootfs_img}" &>/dev/null

    info "Mounting new rootfs image (read-write)..."
    mount -o loop,rw "${new_rootfs_img}" "${ROOTFS_MOUNT_POINT}"

    info "Copying content from original image..."
    cp -a "${ORIG_ROOTFS_MOUNT_POINT}/." "${ROOTFS_MOUNT_POINT}/"

    umount "${ORIG_ROOTFS_MOUNT_POINT}"

    info "Replacing old rootfs image file with the new one..."
    mv "${new_rootfs_img}" "${ROOTFS_IMG_PATH}"
  else
    info "Mounting ${ROOTFS_IMG_PATH} to ${ROOTFS_MOUNT_POINT} (read-write)..."
    mount -o loop,rw "${ROOTFS_IMG_PATH}" "${ROOTFS_MOUNT_POINT}"
  fi

  # Perform copy operations if requested
  if [[ ${#COPY_OPS[@]} -gt 0 ]]; then
    info "Performing copy operations..."
    for ((i = 0; i < ${#COPY_OPS[@]}; i += 2)); do
      local_path="${COPY_OPS[i]}"
      image_path="${COPY_OPS[i + 1]}"
      dest_path="${ROOTFS_MOUNT_POINT}${image_path}"

      if [[ ! -e "$local_path" ]]; then
        error "Local path for --copy not found: $local_path"
        exit 1
      fi
      info "Copying ${local_path} to (root)${image_path}..."
      # Ensure destination directory exists if we are copying a file into a new dir
      mkdir -p "$(dirname "${dest_path}")"
      cp "${local_path}" "${dest_path}"
    done
  fi

  # Run a command if requested
  if [[ -n "$RUN_COMMAND" ]]; then
    setup_chroot_env

    info "Running command in chroot: ${RUN_COMMAND}"
    # Run command, capturing exit code. `|| true` prevents `set -e` from exiting the script.
    chroot "${ROOTFS_MOUNT_POINT}" /bin/bash -c "${RUN_COMMAND}" || true
    RUN_EXIT_CODE=$?

    teardown_chroot_env

    if [[ $RUN_EXIT_CODE -ne 0 ]]; then
      error "Command failed with exit code ${RUN_EXIT_CODE}. Discarding changes."
      exit 1
    fi
  fi

  if [[ "$INTERACTIVE_SHELL" == "true" || "$DEFAULT_ACTION" == "true" ]]; then
    setup_chroot_env

    echo
    success "Chroot environment ready at ${ROOTFS_MOUNT_POINT}"
    echo
    info "Entering shell. Make your changes inside the chroot."
    info "To SAVE changes and repackage the ISO, exit with: exit 0"
    info "To DISCARD changes, exit with any other code (e.g., 'exit 1' or Ctrl+D)."

    # Run shell, capturing exit code. `|| true` prevents `set -e` from exiting the script.
    chroot "${ROOTFS_MOUNT_POINT}" /bin/bash || true
    CHROOT_EXIT_CODE=$?

    teardown_chroot_env

    if [[ $CHROOT_EXIT_CODE -ne 0 ]]; then
      error "Shell exited with code ${CHROOT_EXIT_CODE}. Discarding changes."
      exit 1
    fi
  fi
fi

DO_GRUB_ACTIONS=false
if [[ -n "$GRUB_APPEND_OPTS" || -n "$GRUB_UPDATE_FILE" || "$GRUB_INTERACTIVE" == "true" || -n "$GRUB_DEFAULT_ITEM" || -n "$GRUB_TIMEOUT" ]]; then
  DO_GRUB_ACTIONS=true
fi

# Repackage if any action was performed and succeeded.
if [[ "$DO_ROOTFS_ACTIONS" == "true" || "$DO_GRUB_ACTIONS" == "true" || ${#COPY_ISO_OPS[@]} -gt 0 ]]; then
  success "Changes succeeded, creating a new ISO..."

  XORRISO_ARGS=("-indev" "${ISO_FILE}" "-outdev" "${NEW_ISO_FILENAME}")

  if [[ "$DO_ROOTFS_ACTIONS" == "true" ]]; then
    info "Unmounting rootfs image to save changes..."
    umount "${ROOTFS_MOUNT_POINT}"

    NEW_SQUASHFS_IMG="${WORK_DIR}/new_squashfs.img"
    info "Creating new squashfs image..."
    # use the same parameters as Kiwi in OBS
    mksquashfs "${SQUASHFS_CONTENT_DIR}" "${NEW_SQUASHFS_IMG}" -noappend -b 1M -comp xz -Xbcj x86 &>/dev/null
    XORRISO_ARGS+=("-map" "${NEW_SQUASHFS_IMG}" "${SQUASHFS_IMG_PATH_IN_ISO}")
  fi

  if [[ ${#COPY_ISO_OPS[@]} -gt 0 ]]; then
    for ((i = 0; i < ${#COPY_ISO_OPS[@]}; i += 2)); do
      local_path="${COPY_ISO_OPS[i]}"
      iso_path="${COPY_ISO_OPS[i + 1]}"
      info "Mapping local file ${local_path} to ${iso_path} in new ISO..."
      XORRISO_ARGS+=("-map" "${local_path}" "${iso_path}")
    done
  fi

  if [[ "$DO_GRUB_ACTIONS" == "true" ]]; then
    LOCAL_GRUB_CFG="${WORK_DIR}/grub.cfg"
    info "Extracting ${GRUB_CFG_PATH_IN_ISO} from ${ISO_FILE}..."
    xorriso -osirrox on -indev "${ISO_FILE}" -extract "${GRUB_CFG_PATH_IN_ISO}" "${LOCAL_GRUB_CFG}" &>/dev/null

    if [[ -n "$GRUB_UPDATE_FILE" ]]; then
      info "Updating grub.cfg from ${GRUB_UPDATE_FILE}..."
      if [[ ! -f "$GRUB_UPDATE_FILE" ]]; then
        error "Grub update file not found: $GRUB_UPDATE_FILE"
        exit 1
      fi
      cp "$GRUB_UPDATE_FILE" "$LOCAL_GRUB_CFG"
    fi

    if [[ -n "$GRUB_DEFAULT_ITEM" ]]; then
      if ! grep -q '^[[:space:]]*set[[:space:]]\+default=' "${LOCAL_GRUB_CFG}"; then
        warning "'set default=...' line not found in grub.cfg. Cannot set default entry."
      else
        info "Setting default grub menu entry to '${GRUB_DEFAULT_ITEM}'"
        sed -i "s/^\([[:space:]]*set[[:space:]]\+default=\).*/\1\"${GRUB_DEFAULT_ITEM}\"/" "${LOCAL_GRUB_CFG}"
      fi
    fi

    if [[ -n "$GRUB_TIMEOUT" ]]; then
      if ! grep -q '^[[:space:]]*set[[:space:]]\+timeout=' "${LOCAL_GRUB_CFG}"; then
        warning "'set timeout=...' line not found in grub.cfg. Cannot set timeout."
      else
        info "Setting grub menu timeout to '${GRUB_TIMEOUT}' seconds"
        sed -i "s/^\([[:space:]]*set[[:space:]]\+timeout=\).*/\1${GRUB_TIMEOUT}/" "${LOCAL_GRUB_CFG}"
      fi
    fi

    if [[ -n "$GRUB_APPEND_OPTS" ]]; then
      info "Appending boot options to grub.cfg: '${GRUB_APPEND_OPTS}'"
      awk -v opts_to_append="${GRUB_APPEND_OPTS}" '
				BEGIN { state = 0 }
				/^[[:space:]]*menuentry "Install / { state = 1 }
				/^[[:space:]]*menuentry "Failsafe -- Install / { state = 1 }
				/^[[:space:]]*menuentry "Check Installation Medium"/ { state = 1 }
				(state == 1) && /^[[:space:]]*(linux|linuxefi)/ { $0 = $0 " " opts_to_append; state = 2; }
				/^[[:space:]]*\}/ { state = 0 }
				{ print }
			' "${LOCAL_GRUB_CFG}" >"${LOCAL_GRUB_CFG}.tmp" && mv "${LOCAL_GRUB_CFG}.tmp" "${LOCAL_GRUB_CFG}"
    fi

    if [[ "$GRUB_INTERACTIVE" == "true" ]]; then
      info "Opening grub.cfg for interactive editing with ${EDITOR}..."
      "${EDITOR}" "${LOCAL_GRUB_CFG}"
    fi
    XORRISO_ARGS+=("-map" "${LOCAL_GRUB_CFG}" "${GRUB_CFG_PATH_IN_ISO}")
  fi

  info "Creating new ISO file ${NEW_ISO_FILENAME}..."
  XORRISO_ARGS+=("-boot_image" "any" "replay")
  xorriso "${XORRISO_ARGS[@]}"

  if command -v tagmedia &>/dev/null; then
    info "Calculating the ISO file checksum..."
    tagmedia --digest sha256 "${NEW_ISO_FILENAME}"
  else
    info "Skipping ISO checksum update ('tagmedia' not found)."
  fi

  success "Created ${NEW_ISO_FILENAME}"
  exit 0
fi
