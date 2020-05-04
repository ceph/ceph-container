#!/bin/bash
set -e
source /opt/ceph-container/bin/disk_list.sh

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

function check_device {
  if [[ -z "${OSD_DEVICE}" ]]; then
    log "ERROR: you must declare OSD_DEVICE with a device e.g: /dev/sdb."
    exit 1
  fi
  if [[ ! -b "${OSD_DEVICE}" ]]; then
    log "ERROR: ${OSD_DEVICE} is not a block device!"
    exit 1
  fi
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
  for keyring in $OSD_BOOTSTRAP_KEYRING $MDS_BOOTSTRAP_KEYRING $RGW_BOOTSTRAP_KEYRING $RBD_MIRROR_BOOTSTRAP_KEYRING; do
    mkdir -p "$(dirname "$keyring")"
  done

  # Let's create the ceph directories
  for directory in mon osd mds radosgw tmp mgr; do
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

  # Create the MGR directory
  mkdir -p /var/lib/ceph/mgr/"${CLUSTER}-$MGR_NAME"

  # Adjust the owner of all those directories
  chown "${CHOWN_OPT[@]}" -R ceph. /var/run/ceph/
  find -L /var/lib/ceph/ -mindepth 1 -maxdepth 3 -not \( -user ceph -or -group ceph \) -exec chown "${CHOWN_OPT[@]}" ceph. {} \;
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
    source /opt/ceph-container/bin/osd_directory.sh
    osd_directory
  elif parted --script "${OSD_DEVICE}" print | grep -sqE '^ 1.*ceph data'; then
    log "Bootstrapped OSD found; activating ${OSD_DEVICE}"
    source /opt/ceph-container/bin/osd_disk_activate.sh
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
  fi
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
    if [[ -b "$(dev_part "${OSD_DEVICE}" 3)" ]]; then
      wait_for_file "$(dev_part "${OSD_DEVICE}" 3)"
      chown "${CHOWN_OPT[@]}" ceph. "$(dev_part "${OSD_DEVICE}" 3)"
    else
      wait_for_file "$(dev_part "${OSD_DEVICE}" 5)"
      chown "${CHOWN_OPT[@]}" ceph. "$(dev_part "${OSD_DEVICE}" 5)"
    fi
  fi
  if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    dev_real_path=($(resolve_symlink "$OSD_BLUESTORE_BLOCK_WAL" "$OSD_BLUESTORE_BLOCK_DB"))
    for partition in $(list_dev_partitions "$OSD_DEVICE" "${dev_real_path[@]}"); do
      part_code=$(get_part_typecode "$partition")
      if [[ "$part_code" == "5ce17fce-4087-4169-b7ff-056cc58472be" ||
            "$part_code" == "5ce17fce-4087-4169-b7ff-056cc58473f9" ||
            "$part_code" == "30cd0809-c2b2-499c-8879-2d6b785292be" ||
            "$part_code" == "30cd0809-c2b2-499c-8879-2d6b78529876" ||
            "$part_code" == "89c57f98-2fe5-4dc0-89c1-f3ad0ceff2be" ||
            "$part_code" == "cafecafe-9b03-4f30-b4c6-b4b80ceff106" ]]; then
        wait_for_file "$partition"
        chown "${CHOWN_OPT[@]}" ceph. "$partition"
      fi
    done
  elif [[ ${OSD_FILESTORE} -eq 1 ]]; then
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

function is_dmcrypt () {
  # As soon as we find partitions with TYPE=crypto_LUKS on ${OSD_DEVICE} we can
  # assume this device is part of dmcrypt scenario.

  # To keep compatibility with existing code
  if [ -n "${1}" ]; then
    local OSD_DEVICE
    OSD_DEVICE="${1}"
  fi
  blkid -t TYPE=crypto_LUKS "${OSD_DEVICE}"* -o value -s PARTUUID 1> /dev/null
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

# This function gets the uuid of bluestore partitions
# These uuids will be used to open and close encrypted partitions
function get_dmcrypt_bluestore_uuid {
  DATA_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 1)")
  BLOCK_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 2)")
  BLOCK_PART=$(dev_part "${OSD_DEVICE}" 2)
  LOCKBOX_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 5)")

  export DISK_LIST_SEARCH=block.db_dmcrypt
  start_disk_list
  BLOCK_DB_PART=$(start_disk_list)
  unset DISK_LIST_SEARCH
  if [ -n "${BLOCK_DB_PART}" ]; then
    BLOCK_DB_UUID=$(get_part_uuid "${BLOCK_DB_PART}")
  fi

  export DISK_LIST_SEARCH=block.wal_dmcrypt
  start_disk_list
  BLOCK_WAL_PART=$(start_disk_list)
  unset DISK_LIST_SEARCH
  if [ -n "${BLOCK_WAL_PART}" ]; then
    BLOCK_WAL_UUID=$(get_part_uuid "${BLOCK_WAL_PART}")
  fi
}

# This function gets the uuid of filestore partitions
# These uuids will be used to open and close encrypted partitions
function get_dmcrypt_filestore_uuid {
  DATA_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 1)")
  # shellcheck disable=SC2034
  # we could be in the middle of an update from Jewel to Luminous then the partition is number 3
  if [[ -b "$(dev_part "${OSD_DEVICE}" 3)" ]]; then
    LOCKBOX_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 3)")
  else
    LOCKBOX_UUID=$(get_part_uuid "$(dev_part "${OSD_DEVICE}" 5)")
  fi
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
  if [[ -n "${BLOCK_DB_UUID}" && ! -e /dev/mapper/"${BLOCK_DB_UUID}" ]]; then
    open_encrypted_part "${BLOCK_DB_UUID}" "${BLOCK_DB_PART}" "${DATA_UUID}"
  fi
  if [[ -n "${BLOCK_WAL_UUID}" && ! -e /dev/mapper/"${BLOCK_WAL_UUID}" ]]; then
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

# Closes all bluestore encrypted partitions
function close_encrypted_parts_bluestore {
  # Open LUKS device(s) if necessary
  if [[ -e /dev/mapper/"${DATA_UUID}" ]]; then
    close_encrypted_part "${DATA_UUID}" "${DATA_PART}" "${DATA_UUID}"
  fi
  if [[ -e /dev/mapper/"${BLOCK_UUID}" ]]; then
    close_encrypted_part "${BLOCK_UUID}" "${BLOCK_PART}" "${DATA_UUID}"
  fi
  if [[ -n "${BLOCK_DB_UUID}" && -e /dev/mapper/"${BLOCK_DB_UUID}" ]]; then
    close_encrypted_part "${BLOCK_DB_UUID}" "${BLOCK_DB_PART}" "${DATA_UUID}"
  fi
  if [[ -n "${BLOCK_WAL_UUID}" && -e /dev/mapper/"${BLOCK_WAL_UUID}" ]]; then
    close_encrypted_part "${BLOCK_WAL_UUID}" "${BLOCK_WAL_PART}" "${DATA_UUID}"
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
  ceph_fsid=$(ceph-conf --lookup fsid -c /etc/ceph/"$CLUSTER".conf)
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

# Detect how much ram is available
function get_available_ram {
  limit_in_bytes="/sys/fs/cgroup/memory/memory.limit_in_bytes"
  memory_limit=$(cat $limit_in_bytes)
  # 8 ExaBytes is the value of an unbounded device
  if  [ "${memory_limit}" = "9223372036854771712" ]; then
    # Looks like we are not in a container
    # Let's report the MemAvailable on this system
    echo $(( $(awk '/MemAvailable/{print $2}' /proc/meminfo) * 1024))
  else
    current_usage=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes)
    echo $(( memory_limit - current_usage ))
  fi
}

# Convert MB into bytes
function MB_to_bytes() {
  echo $(($1 * 1024 * 1024))
}

# Convert bytes into MB
function bytes_to_MB() {
  echo $(($1 / 1024 / 1024))
}

function tune_memory {
  local available_memory="$1"
  _50MB="$(MB_to_bytes 50)"
  _128MB="$(MB_to_bytes 128)"
  _4096MB="$(MB_to_bytes 4096)"

  # Don't try to tune the cluster if its already done
  if grep -q -e osd_memory_target -e osd_memory_base -e osd_memory_cache_min /etc/ceph/"${CLUSTER}".conf; then
    log "/etc/ceph/${CLUSTER}.conf is already memory tuned"
    return
  fi

  if [ -z "$available_memory" ]; then
    log "The memory detection failed, cannot tune memory"
    return
  fi

  log "Found $(bytes_to_MB "$available_memory")MB of available memory ($available_memory bytes)"
  # If the system have a lot of ram, it's difficult to consider that everything will be given to ceph
  # As the current default of ceph is around 4GB, let's cap the memory assigned to ceph at 4GB.
  if [ "$available_memory" -gt "${_4096MB}" ]; then
    log "More than 4GB of available memory found. Caping to 4GB to avoid consuming all memory for ceph"
    available_memory="$_4096MB"
  fi

  # osd_memory_target is 50MB below the available memory
  # That let some room for other processes (to be adjusted)
  osd_memory_target=$((available_memory - _50MB))
  if [ "$osd_memory_target" -le "${_128MB}" ]; then
    log  "osd_memory_target ($(bytes_to_MB $osd_memory_target)MB) is too small, cannot tune memory."
    return
  fi

  # osd_memory_base is set to half of the memory available
  osd_memory_base=$((available_memory / 2))
  if [ "$osd_memory_base" -le "${_128MB}" ]; then
    log  "osd_memory_base ($(bytes_to_MB $osd_memory_base)MB) is too small, cannot tune memory."
    return
  fi

  # let's put the cache_min at the middle between memory_base and memory_target
  osd_memory_cache_min=$(((osd_memory_target - osd_memory_base) / 2 + osd_memory_base))
  log "Tuning memory : osd_memory_base=$(bytes_to_MB $osd_memory_base)MB, osd_memory_cache_min=$(bytes_to_MB $osd_memory_cache_min)MB, osd_memory_target=$(bytes_to_MB $osd_memory_target)MB"

  cat << ENDHERE >> /etc/ceph/"${CLUSTER}".conf
osd_memory_target = $osd_memory_target
osd_memory_base = $osd_memory_base
osd_memory_cache_min = $osd_memory_cache_min
ENDHERE
}

# Map dmcrypt data device
function dmcrypt_data_map() {
  for lockbox in $(blkid -t PARTLABEL="ceph lockbox" -o device | tr '\n' ' '); do
    if [[ "${lockbox}" =~ ^/dev/(cciss|nvme|loop) ]]; then
      OSD_DEVICE=${lockbox:0:-2}
    else
      OSD_DEVICE=${lockbox:0:-1}
    fi
    DATA_PART=$(dev_part "${OSD_DEVICE}" 1)
    DATA_UUID=$(get_part_uuid "${DATA_PART}")
    if [[ -b "$(dev_part "${OSD_DEVICE}" 3)" ]]; then
      LOCKBOX_PART=$(dev_part "${OSD_DEVICE}" 3)
    else
      LOCKBOX_PART=$(dev_part "${OSD_DEVICE}" 5)
    fi
    LOCKBOX_UUID=$(get_part_uuid "${LOCKBOX_PART}")
    mount_lockbox "${DATA_UUID}" "${LOCKBOX_UUID}"
    ceph-disk --setuser ceph --setgroup disk activate --dmcrypt --no-start-daemon ${DATA_PART} || true
  done
}
