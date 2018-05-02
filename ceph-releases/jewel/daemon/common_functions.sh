#!/bin/bash
set -e
source disk_list.sh

# log arguments with timestamp
function log {
  if [ -z "$*" ]; then
    return 1
  fi

  local timestamp
  timestamp=$(date '+%F %T')
  echo "$timestamp  $0: $*"
  return 0
}

# ceph config file exists or die
function check_config {
  if [[ ! -e /etc/ceph/${CLUSTER}.conf ]]; then
    log "ERROR- /etc/ceph/${CLUSTER}.conf must exist; get it from your existing mon"
    exit 1
  fi
}

# ceph admin key exists or die
function check_admin_key {
  if [[ ! -e $ADMIN_KEYRING ]]; then
    log "ERROR- $ADMIN_KEYRING must exist; get it from your existing mon"
    exit 1
  fi
}

# Given two strings, return the length of the shared prefix
function prefix_length {
  local maxlen
  maxlen=${#1}
  for ((i=maxlen-1;i>=0;i--)); do
    if [[ "${1:0:i}" == "${2:0:i}" ]]; then
      echo $i
      return
    fi
  done
}

# Test if a command line tool is available
function is_available {
  command -v "$@" &>/dev/null
}

# create the mandatory directories
function create_mandatory_directories {
  # Let's create the bootstrap directories
  for keyring in $OSD_BOOTSTRAP_KEYRING $MDS_BOOTSTRAP_KEYRING $RGW_BOOTSTRAP_KEYRING; do
    mkdir -p "$(dirname "$keyring")"
  done

  # Let's create the ceph directories
  for directory in mon osd mds radosgw tmp; do
    mkdir -p /var/lib/ceph/$directory
  done

  # Make the monitor directory
  mkdir -p "$MON_DATA_DIR"

  # Create socket directory
  mkdir -p /var/run/ceph

  # Create radosgw directory
  mkdir -p /var/lib/ceph/radosgw/"${CLUSTER}"-rgw."${RGW_NAME}"

  # Create the MDS directory
  mkdir -p /var/lib/ceph/mds/"${CLUSTER}-${MDS_NAME}"

  # Adjust the owner of all those directories
  chown "${CHOWN_OPT[@]}" -R ceph. /var/run/ceph/
  find -L /var/lib/ceph/ -mindepth 1 -maxdepth 3 -exec chown "${CHOWN_OPT[@]}" ceph. {} \;
}

# Print resolved symbolic links of a device
function resolve_symlink {
  readlink -f "${@}"
}

# Calculate proper device names, given a device and partition number
function dev_part {
  local osd_device=${1}
  local osd_partition=${2}

  if [[ -L ${osd_device} ]]; then
    # This device is a symlink. Work out it's actual device
    local actual_device
    actual_device=$(readlink -f "${osd_device}")
    if [[ "${actual_device:0-1:1}" == [0-9] ]]; then
      local desired_partition="${actual_device}p${osd_partition}"
    else
      local desired_partition="${actual_device}${osd_partition}"
    fi
    # Now search for a symlink in the directory of $osd_device
    # that has the correct desired partition, and the longest
    # shared prefix with the original symlink
    local symdir
    symdir=$(dirname "${osd_device}")
    local link=""
    local pfxlen=0
    for option in ${symdir}/*; do
      [[ -e $option ]] || break
      if [[ $(readlink -f "$option") == "$desired_partition" ]]; then
        local optprefixlen
        optprefixlen=$(prefix_length "$option" "$osd_device")
        if [[ $optprefixlen > $pfxlen ]]; then
          link=$option
          pfxlen=$optprefixlen
        fi
      fi
    done
    if [[ $pfxlen -eq 0 ]]; then
      >&2 log "Could not locate appropriate symlink for partition ${osd_partition} of ${osd_device}"
      exit 1
    fi
    echo "$link"
  elif [[ "${osd_device:0-1:1}" == [0-9] ]]; then
    echo "${osd_device}p${osd_partition}"
  else
    echo "${osd_device}${osd_partition}"
  fi
}

function osd_trying_to_determine_scenario {
  : "${OSD_DEVICE:=none}"
  if [[ ${OSD_DEVICE} == "none" ]]; then
    log "Bootstrapped OSD(s) found; using OSD directory"
    source osd_directory.sh
    osd_directory
  elif parted --script "${OSD_DEVICE}" print | grep -sqE '^ 1.*ceph data'; then
    log "Bootstrapped OSD found; activating ${OSD_DEVICE}"
    source osd_disk_activate.sh
    osd_activate
  else
    log "Device detected, assuming ceph-disk scenario is desired"
    log "Preparing and activating ${OSD_DEVICE}"
    osd_disk
  fi
}

function get_osd_dev {
  for i in ${OSD_DISKS}; do
    local osd_id
    osd_id=$(echo "${i}"|sed 's/\(.*\):\(.*\)/\1/')
    local osd_dev
    osd_dev="/dev/$(echo "${i}"|sed 's/\(.*\):\(.*\)/\2/')"
    if [[ "${osd_id}" == "${1}" ]]; then
      echo -n "${osd_dev}"
    fi
  done
}

function unsupported_scenario {
  echo "ERROR: '${CEPH_DAEMON}' scenario or key/value store '${KV_TYPE}' is not supported by this distribution."
  echo "ERROR: for the list of supported scenarios, please refer to your vendor."
  exit 1
}

function is_integer {
  # This function is about saying if the passed argument is an integer
  # Supports also negative integers
  # We use $@ here to consider everything given as parameter and not only the
  # first one : that's mainly for splited strings like "10 10"
  for arg in "$@"; do
    [[ $arg =~ ^-?[0-9]+$ ]]
  done
}

# Transform any set of strings to lowercase
function to_lowercase {
  echo "${@,,}"
}

# Transform any set of strings to uppercase
function to_uppercase {
  echo "${@^^}"
}

# Replace any variable separated with comma with space
# e.g: DEBUG=foo,bar will become:
# echo ${DEBUG//,/ }
# foo bar
function comma_to_space {
  echo "${@//,/ }"
}

# Get based distro by discovering the package manager
function get_package_manager {
  if is_available rpm; then
    OS_VENDOR=redhat
  elif is_available dpkg; then
    OS_VENDOR=ubuntu
  fi
}

# Determine if current distribution is an Ubuntu-based distribution
function is_ubuntu {
  get_package_manager
  [[ "$OS_VENDOR" == "ubuntu" ]]
}

# Determine if current distribution is a RedHat-based distribution
function is_redhat {
  get_package_manager
  [[ "$OS_VENDOR" == "redhat" ]]
}

# Wait for a file to exist, regardless of the type
function wait_for_file {
  timeout 10 bash -c "while [ ! -e ${1} ]; do echo 'Waiting for ${1} to show up' && sleep 1 ; done"
}

function valid_scenarios {
  if [ -n "$EXCLUDED_TAGS" ]; then
    for tag in $EXCLUDED_TAGS; do
      ALL_SCENARIOS=${ALL_SCENARIOS/$tag /}
    done
  fi
  log "Valid values for CEPH_DAEMON are $(to_uppercase "$ALL_SCENARIOS")."
  log "Valid values for the daemon parameter are $ALL_SCENARIOS"
}

function invalid_ceph_daemon {
  if [ -z "$CEPH_DAEMON" ]; then
    log "ERROR- One of CEPH_DAEMON or a daemon parameter must be defined as the name of the daemon you want to deploy."
    valid_scenarios
    exit 1
  else
    log "ERROR- unrecognized scenario."
    valid_scenarios
  fi
}

function get_osd_path {
  echo "$OSD_PATH_BASE-$1/"
}

# List all the partitions on a block device
function list_dev_partitions {
  # We need to remove the /dev/ part of the device name
  # since /proc/partitions has entries like sda only.
  # However we return a complete device name e.g: /dev/sda
  for args in "${@}"; do
    grep -Eo "${args#/dev/}[0-9]" < /proc/partitions | while read -r line; do
      echo "/dev/$line"
    done
  done
}

# Find the typecode of a partition
function get_part_typecode {
  for part in "${@}"; do
    sgdisk --info="${part: -1}" "${part%?}" | awk '/Partition GUID code/ {print tolower($4)}'
  done
}

function apply_ceph_ownership_to_disks {
  if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
    wait_for_file "$(dev_part "${OSD_DEVICE}" 3)"
    chown "${CHOWN_OPT[@]}" ceph. "$(dev_part "${OSD_DEVICE}" 3)"
  fi
  if [[ ${OSD_FILESTORE} -eq 1 ]]; then
    if [[ -n "${OSD_JOURNAL}" ]]; then
      wait_for_file "${OSD_JOURNAL}"
      chown "${CHOWN_OPT[@]}" ceph. "${OSD_JOURNAL}"
    else
      wait_for_file "$(dev_part "${OSD_DEVICE}" 2)"
      chown "${CHOWN_OPT[@]}" ceph. "$(dev_part "${OSD_DEVICE}" 2)"
    fi
  fi
  wait_for_file "$(dev_part "${OSD_DEVICE}" 1)"
  chown "${CHOWN_OPT[@]}" ceph. "$(dev_part "${OSD_DEVICE}" 1)"
}

# Get partition uuid of a given partition
function get_part_uuid {
  blkid -o value -s PARTUUID "${1}"
}

function ceph_health {
  local bootstrap_user=$1
  local bootstrap_key=$2

  if ! timeout 10 ceph "${CLI_OPTS[@]}" --name "$bootstrap_user" --keyring "$bootstrap_key" health; then
    log "Timed out while trying to reach out to the Ceph Monitor(s)."
    log "Make sure your Ceph monitors are up and running in quorum."
    log "Also verify the validity of $bootstrap_user keyring."
    exit 1
  fi
}

function is_net_ns {
  # if we run a container with --net=host we will see all the connections
  # if we don't, we should see the file header
  [[ $(wc -l < /proc/net/tcp) == 1 ]]
}

function is_pid_ns {
  # if we run a container with --pid=host we will see all the processes
  # if we don't, we should see 3 (pid 1 and ps and the new line)
  [[ $(ps --no-header x | wc -l) -gt 3 ]]
}

# This function is only used when CEPH_DAEMON=demo
# For a 'demo' container, we must ensure there is no Ceph files
function detect_ceph_files {
  if [ -f /etc/ceph/I_AM_A_DEMO ] || [ -f /var/lib/ceph/I_AM_A_DEMO ]; then
    log "Found residual files of a demo container."
    log "This looks like a restart, processing."
    return 0
  fi
  if [ -d /var/lib/ceph ] || [ -d /etc/ceph ]; then
    # For /etc/ceph, it always contains a 'rbdmap' file so we must check for length > 1
    if [[ "$(find /var/lib/ceph/ -mindepth 3 -maxdepth 3 -type f | wc -l)" != 0 ]] || [[ "$(find /etc/ceph -mindepth 1 -type f| wc -l)" -gt "1" ]]; then
      log "I can see existing Ceph files, please remove them!"
      log "To run the demo container, remove the content of /var/lib/ceph/ and /etc/ceph/"
      log "Before doing this, make sure you are removing any sensitive data."
      exit 1
    fi
  fi
}

# This function gets the uuid of filestore partitions
# These uuids will be used to open and close encrypted partitions
function get_dmcrypt_filestore_uuid {
  DATA_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 1)")
  # shellcheck disable=SC2034
  LOCKBOX_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 3)")
  export DISK_LIST_SEARCH=journal_dmcrypt
  start_disk_list
  JOURNAL_PART=$(start_disk_list)
  unset DISK_LIST_SEARCH
  JOURNAL_UUID=$(get_part_uuid "${JOURNAL_PART}")
}

# Opens all bluestore encrypted partitions
function open_encrypted_parts_bluestore {
  # Open LUKS device(s) if necessary
  if [[ ! -e /dev/mapper/"${DATA_UUID}" ]]; then
    open_encrypted_part "${DATA_UUID}" "${DATA_PART}" "${DATA_UUID}"
  fi
  if [[ ! -e /dev/mapper/"${BLOCK_UUID}" ]]; then
    open_encrypted_part "${BLOCK_UUID}" "${BLOCK_PART}" "${DATA_UUID}"
  fi
  if [[ ! -e /dev/mapper/"${BLOCK_DB_UUID}" ]]; then
    open_encrypted_part "${BLOCK_DB_UUID}" "${BLOCK_DB_PART}" "${DATA_UUID}"
  fi
  if [[ ! -e /dev/mapper/"${BLOCK_WAL_UUID}" ]]; then
    open_encrypted_part "${BLOCK_WAL_UUID}" "${BLOCK_WAL_PART}" "${DATA_UUID}"
  fi
}

# Opens all filestore encrypted partitions
function open_encrypted_parts_filestore {
  # Open LUKS device(s) if necessary
  if [[ ! -e /dev/mapper/"${DATA_UUID}" ]]; then
    open_encrypted_part "${DATA_UUID}" "${DATA_PART}" "${DATA_UUID}"
  fi
  if [[ ! -e /dev/mapper/"${JOURNAL_UUID}" ]]; then
    open_encrypted_part "${JOURNAL_UUID}" "${JOURNAL_PART}" "${DATA_UUID}"
  fi
}

# Closes all filestore encrypted partitions
function close_encrypted_parts_filestore {
  # Open LUKS device(s) if necessary
  if [[ -e /dev/mapper/"${DATA_UUID}" ]]; then
    close_encrypted_part "${DATA_UUID}" "${DATA_PART}" "${DATA_UUID}"
  fi
  if [[ -e /dev/mapper/"${JOURNAL_UUID}" ]]; then
    close_encrypted_part "${JOURNAL_UUID}" "${JOURNAL_PART}" "${DATA_UUID}"
  fi
}

# Opens an encrypted partition
function open_encrypted_part {
  # $1 is partition uuid
  # $2 is partition name, e.g: /dev/sda1
  # $3 is the 'ceph data' partition uuid, this is the one used by the lockbox
  log "Opening encrypted device $1"
  ceph "${CLI_OPTS[@]}" --name client.osd-lockbox."${3}" \
  --keyring /var/lib/ceph/osd-lockbox/"${3}"/keyring \
  config-key \
  get \
  dm-crypt/osd/"${3}"/luks 2> /dev/null | base64 -d | cryptsetup --key-file - luksOpen "${2}" "${1}"
}

function mount_lockbox {
  log "Mounting LOCKBOX directory"
  # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
  # Ceph bug tracker: http://tracker.ceph.com/issues/18945
  mkdir -p /var/lib/ceph/osd-lockbox/"${1}"
  mount /dev/disk/by-partuuid/"${2}" /var/lib/ceph/osd-lockbox/"${1}" || true
  local ceph_fsid
  local cluster_name
  cluster_name=$(basename "$(grep -R fsid /etc/ceph/ | grep -oE '^[^.]*')")
  ceph_fsid=$(ceph-conf --lookup fsid -c /etc/ceph/"$cluster_name".conf)
  echo "$ceph_fsid" > /var/lib/ceph/osd-lockbox/"${1}"/ceph_fsid
  chown "${CHOWN_OPT[@]}" ceph. /var/lib/ceph/osd-lockbox/"${1}"/ceph_fsid
}

# Closes an encrypted partition
function close_encrypted_part {
  # $1 is partition uuid
  # $2 is partition name, e.g: /dev/sda1
  # $3 is the 'ceph data' partition uuid, this is the one used by the lockbox
  log "Closing encrypted device $1"
  ceph "${CLI_OPTS[@]}" --name client.osd-lockbox."${3}" \
  --keyring /var/lib/ceph/osd-lockbox/"${3}"/keyring \
  config-key \
  get \
  dm-crypt/osd/"${3}"/luks 2> /dev/null | base64 -d | cryptsetup --key-file - luksClose "${1}"
}

function umount_lockbox {
  log "Unmounting LOCKBOX directory"
  # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
  # Ceph bug tracker: http://tracker.ceph.com/issues/18944
  DATA_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 1)")
  umount /var/lib/ceph/osd-lockbox/"${DATA_UUID}" || true
}

function ami_privileged {
  if ! blkid > /dev/null || ! stat /dev/disk/ > /dev/null; then
    log "ERROR: I don't have enough privileges, I can't discover devices on that machine."
    log "ERROR: run me as a privileged container with the following options"
    log "ERROR: --privileged=true -v /dev/:/dev/"
    exit 1
  fi
  # NOTE (leseb): when not running with --privileged=true -v /dev/:/dev/
  # lsblk is not able to get device mappers path and is complaining.
  # That's why stderr is suppressed in /dev/null
}

function ami_privileged {
  if ! blkid > /dev/null || ! stat /dev/disk/ > /dev/null; then
    log "ERROR: I don't have enough privileges, I can't discover devices on that machine."
    log "ERROR: run me as a privileged container with the following options"
    log "ERROR: --privileged=true -v /dev/:/dev/"
    exit 1
  fi
  # NOTE (leseb): when not running with --privileged=true -v /dev/:/dev/
  # lsblk is not able to get device mappers path and is complaining.
  # That's why stderr is suppressed in /dev/null
}

function add_osd_to_crush {
  # only add crush_location if the current is empty
  local crush_loc
  OSD_KEYRING="$OSD_PATH/keyring"
  # shellcheck disable=SC2153
  crush_loc=$(ceph "${CLI_OPTS[@]}" --name=osd."${OSD_ID}" --keyring="$OSD_KEYRING" osd find "${OSD_ID}"|python -c 'import sys, json; print(json.load(sys.stdin)["crush_location"])')
  if [[ "$crush_loc" == "{}" ]]; then
    ceph "${CLI_OPTS[@]}" --name=osd."${OSD_ID}" --keyring="$OSD_KEYRING" osd crush create-or-move -- "${OSD_ID}" "${OSD_WEIGHT}" "${CRUSH_LOCATION[@]}"
  fi
}

function calculate_osd_weight {
  OSD_PATH=$(get_osd_path "$OSD_ID")
  OSD_WEIGHT=$(df -P -k "$OSD_PATH" | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
}
