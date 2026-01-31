#!/bin/bash
#
# A script updating the boot/grub2/grub.cfg in an ISO file, allows interactive
# editing, replacing the file or appending specified boot parameters.
#
# Dependencies: xorriso, tagmedia, sha256sum, awk, $EDITOR
#

set -e          # Exit immediately if a command exits with a non-zero status.
set -u          # Treat unset variables as an error when substituting.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Configuration ---
# The path to the grub.cfg file inside the ISO.
# You might need to change this depending on your ISO's structure.
# Common paths are /boot/grub/grub.cfg or /boot/grub2/grub.cfg
GRUB_CFG_PATH_IN_ISO="/boot/grub2/grub.cfg"

# Use the EDITOR environment variable, or default to 'vim'.
EDITOR="${EDITOR:-vim}"

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

progress() {
  echo "${GREEN}${*}${NC}"
}

# --- Functions ---

# Ensures the temporary directory is cleaned up on script exit.
cleanup() {
  # The '-n' and '-d' checks prevent errors if the script fails before TEMP_DIR is set.
  if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

# Extracts the grub.cfg file from the ISO.
# $1: Source ISO file
# $2: Destination path for grub.cfg
extract_grub_cfg() {
  local iso_file="$1"
  local dest_path="$2"

  echo "Extracting ${GRUB_CFG_PATH_IN_ISO} from ${iso_file}..."
  if ! xorriso -osirrox on -indev "${iso_file}" -extract "${GRUB_CFG_PATH_IN_ISO}" "${dest_path}" &>/dev/null; then
    error "Failed to extract ${GRUB_CFG_PATH_IN_ISO}. Please check if the path is correct for your ISO file."
    exit 1
  fi
}

# Checks if the output file already exists to prevent overwriting.
check_output_file_exists() {
  local new_iso_filename="${OUTPUT_ISO:-${ORIGINAL_ISO%.iso}-edited.iso}"
  if [[ -e "$new_iso_filename" ]]; then
    error "Output file ${new_iso_filename} already exists."
    error "Remove it or specify a different output file with --output parameter."
    exit 1
  fi
}

# Creates a new ISO with the updated grub.cfg
# $1: Path to the local grub.cfg to be included in the new ISO
create_new_iso() {
  local source_grub_cfg="$1"
  local new_iso_filename="${OUTPUT_ISO:-${ORIGINAL_ISO%.iso}-edited.iso}"

  progress "Creating new ISO file ${new_iso_filename}..."
  xorriso -indev "${ORIGINAL_ISO}" -outdev "${new_iso_filename}" -map "${source_grub_cfg}" "${GRUB_CFG_PATH_IN_ISO}" -boot_image 'any' 'replay'

  if [[ "$SKIP_TAGMEDIA" == "false" ]]; then
    if command -v tagmedia &>/dev/null; then
      echo "Calculating the ISO file checksum..."
      tagmedia --digest sha256 "${new_iso_filename}"
    else
      warning "The 'tagmedia' tool was not found. Skipping checksum update."
      warning "It can be installed with command 'sudo zypper install checkmedia'"
    fi
  else
    echo "Skipping ISO checksum update."
  fi
  progress "Successfully created new ISO ${new_iso_filename}"
}

# Displays usage information and exits.
usage() {
  echo "Script for updating the grub.cfg file in an ISO image file."
  echo ""
  echo "Usage: $0 [options] <iso_file>"
  echo ""
  echo "Modes (choose one):"
  echo "  (default)         Interactively edit grub.cfg and create a new image."
  echo "  --extract [path]  Extract grub.cfg to [path] (default: ./grub.cfg) and exit."
  echo "  --update <file>   Update grub.cfg from a local file and create a new image."
  echo "  --append <opts>   Append kernel options to 'Install' menu entries."
  echo ""
  echo "Options:"
  echo "  -h, --help        Show this help message and exit."
  echo "  --output <file>   Specify the output ISO file name. (Not for --extract mode)."
  echo "                    If not specified creates a new file with *-edited.iso suffix"
  echo "  --skip-tagmedia   Do not run 'tagmedia' to update the ISO checksum."
  exit 1
}

# --- Main Script ---

MODE="interactive"
ORIGINAL_ISO=""
OUTPUT_ISO=""
EXTRACT_PATH=""
USER_GRUB_CFG=""
APPEND_OPTS=""
SKIP_TAGMEDIA=false

# 1. Argument Parsing
if [[ $# -eq 0 ]]; then
  usage
fi

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    ;;
  --extract)
    if [[ "$MODE" != "interactive" ]]; then
      error "Only one mode can be specified."
      usage
    fi
    MODE="extract"
    # Check for optional argument. It is consumed if it exists and is not an option.
    if [[ -n "${2:-}" && ! "$2" =~ ^- && $# -gt 2 ]]; then
      EXTRACT_PATH="$2"
      shift
    fi
    shift
    ;;
  --update)
    if [[ "$MODE" != "interactive" ]]; then
      error "Only one mode can be specified."
      usage
    fi
    MODE="update"
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--update requires a source file."
      usage
    fi
    USER_GRUB_CFG="$2"
    shift 2
    ;;
  --append)
    if [[ "$MODE" != "interactive" ]]; then
      error "Only one mode can be specified."
      usage
    fi
    MODE="append"
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--append requires an options string."
      usage
    fi
    APPEND_OPTS="$2"
    shift 2
    ;;
  --output)
    if [[ -n "$OUTPUT_ISO" ]]; then
      error "--output can only be specified once."
      usage
    fi
    if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
      error "--output requires a file path."
      usage
    fi
    OUTPUT_ISO="$2"
    shift 2
    ;;
  --skip-tagmedia)
    SKIP_TAGMEDIA=true
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

# 2. Validate arguments and environment
if [[ "${#POSITIONAL_ARGS[@]}" -ne 1 ]]; then
  error "Exactly one ISO file must be specified."
  usage
fi
ORIGINAL_ISO="${POSITIONAL_ARGS[0]}"
if [[ ! -f "$ORIGINAL_ISO" ]]; then
  error "File not found $ORIGINAL_ISO"
  exit 1
fi
if ! command -v xorriso &>/dev/null; then
  error "The 'xorriso' tool is not installed. Please install it to continue."
  error "It can be installed with command: sudo zypper install xorriso"
  exit 1
fi
if [[ "$MODE" == "extract" && -z "$EXTRACT_PATH" ]]; then
  EXTRACT_PATH="grub.cfg" # Default path if not given
fi

# 3. Execute logic based on mode
case "$MODE" in
"extract")
  if [[ -n "$OUTPUT_ISO" ]]; then warning "--output is ignored with --extract."; fi
  extract_grub_cfg "${ORIGINAL_ISO}" "${EXTRACT_PATH}"
  progress "Successfully extracted ${GRUB_CFG_PATH_IN_ISO} to ${EXTRACT_PATH}"
  ;;

"update")
  if [[ ! -f "$USER_GRUB_CFG" ]]; then
    error "Input file $USER_GRUB_CFG not found"
    exit 1
  fi
  progress "Updating ${GRUB_CFG_PATH_IN_ISO} from ${USER_GRUB_CFG}..."
  check_output_file_exists
  create_new_iso "${USER_GRUB_CFG}"
  ;;

"append")
  # Setup temporary directory and cleanup trap
  TEMP_DIR=$(mktemp -d)
  trap cleanup EXIT
  LOCAL_GRUB_CFG="${TEMP_DIR}/grub.cfg"

  # Extract grub.cfg
  extract_grub_cfg "${ORIGINAL_ISO}" "${LOCAL_GRUB_CFG}"

  progress "Appending boot options '${APPEND_OPTS}'..."
  CHECKSUM_BEFORE=$(sha256sum "${LOCAL_GRUB_CFG}")

  # Update the menu entries
  awk -v opts_to_append="${APPEND_OPTS}" '
    # State: 0=outside, 1=inside relevant menuentry, 2=inside but already modified
    BEGIN { state = 0 }
    # Match start of relevant menuentry
    /^[[:space:]]*menuentry "Install / { state = 1 }
    /^[[:space:]]*menuentry "Failsafe -- Install / { state = 1 }
    /^[[:space:]]*menuentry "Check Installation Medium"/ { state = 1 }
    # If inside relevant menuentry, look for linux/linuxefi line
    (state == 1) && /^[[:space:]]*(linux|linuxefi)/ {
      $0 = $0 " " opts_to_append
      state = 2 # Mark as done for this block
    }
    # Match end of any menuentry block
    /^[[:space:]]*\}/ { state = 0 }
    # Print the (possibly modified) line
    { print }
  ' "${LOCAL_GRUB_CFG}" >"${LOCAL_GRUB_CFG}.tmp" && mv "${LOCAL_GRUB_CFG}.tmp" "${LOCAL_GRUB_CFG}"

  CHECKSUM_AFTER=$(sha256sum "${LOCAL_GRUB_CFG}")
  if [[ "$CHECKSUM_BEFORE" == "$CHECKSUM_AFTER" ]]; then
    warning "No matching 'Install' menu entries found to append options to. No changes made."
    exit 0
  fi

  check_output_file_exists
  create_new_iso "${LOCAL_GRUB_CFG}"
  ;;

"interactive")
  # Check if the editor is available
  if ! command -v "${EDITOR}" &>/dev/null; then
    error "Editor '${EDITOR}' not found. Please install it or set the \$EDITOR environment variable."
    exit 1
  fi

  # Setup temporary directory and cleanup trap
  TEMP_DIR=$(mktemp -d)
  trap cleanup EXIT
  LOCAL_GRUB_CFG="${TEMP_DIR}/grub.cfg"

  # Extract grub.cfg
  extract_grub_cfg "${ORIGINAL_ISO}" "${LOCAL_GRUB_CFG}"

  # Check if output file exists before opening editor to prevent losing changes
  check_output_file_exists
  # Allow user to edit the file
  echo "Opening ${LOCAL_GRUB_CFG} with ${EDITOR} for editing..."
  CHECKSUM_BEFORE=$(sha256sum "${LOCAL_GRUB_CFG}")
  "${EDITOR}" "${LOCAL_GRUB_CFG}"
  CHECKSUM_AFTER=$(sha256sum "${LOCAL_GRUB_CFG}")

  if [[ "$CHECKSUM_BEFORE" == "$CHECKSUM_AFTER" ]]; then
    echo "No changes detected in grub.cfg. Aborting."
    exit 0
  fi

  create_new_iso "${LOCAL_GRUB_CFG}"
  ;;
esac
