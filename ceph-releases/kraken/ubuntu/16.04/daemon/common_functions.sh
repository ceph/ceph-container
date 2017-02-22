#!/bin/bash
set -e

# log arguments with timestamp
function log {
  if [ -z "$*" ]; then
    return 1
  fi

  TIMESTAMP=$(date '+%F %T')
  echo "${TIMESTAMP}  $0: $*"
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
  if [[ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]]; then
      log "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
      exit 1
  fi
}

# Given two strings, return the length of the shared prefix
function prefix_length {
  local maxlen=${#1}
  for ((i=maxlen-1;i>=0;i--)); do
    if [[ "${1:0:i}" == "${2:0:i}" ]]; then
      echo $i
      return
    fi
  done
}


# create the mandatory directories
function create_mandatory_directories {
  # Let's create the bootstrap directories
  for directory in osd mds rgw; do
    mkdir -p /var/lib/ceph/bootstrap-$directory
  done

  # Let's create the ceph directories
  for directory in mon osd mds radosgw tmp; do
    mkdir -p /var/lib/ceph/$directory
  done

  # Create socket directory
  mkdir -p /var/run/ceph

  # Adjust the owner of all those directories
  chown -R ceph. /var/run/ceph/ /var/lib/ceph/*
}


# Calculate proper device names, given a device and partition number
function dev_part {
  local osd_device=${1}
  local osd_partition=${2}

  if [[ -L ${osd_device} ]]; then
    # This device is a symlink. Work out it's actual device
    local actual_device=$(readlink -f ${osd_device})
    local bn=$(basename ${osd_device})
    if [[ "${actual_device:0-1:1}" == [0-9] ]]; then
      local desired_partition="${actual_device}p${osd_partition}"
    else
      local desired_partition="${actual_device}${osd_partition}"
    fi
    # Now search for a symlink in the directory of $osd_device
    # that has the correct desired partition, and the longest
    # shared prefix with the original symlink
    local symdir=$(dirname ${osd_device})
    local link=""
    local pfxlen=0
    for option in $(ls $symdir); do
    if [[ $(readlink -f $symdir/$option) == $desired_partition ]]; then
      local optprefixlen=$(prefix_length $option $bn)
      if [[ $optprefixlen > $pfxlen ]]; then
        link=$symdir/$option
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
  if [ -z "${OSD_DEVICE}" ]; then
    log "Bootstrapped OSD(s) found; using OSD directory"
    source osd_directory.sh
    osd_directory
  elif $(parted --script ${OSD_DEVICE} print | egrep -sq '^ 1.*ceph data'); then
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
  for i in ${OSD_DISKS}
   do
    osd_id=$(echo ${i}|sed 's/\(.*\):\(.*\)/\1/')
    osd_dev="/dev/$(echo ${i}|sed 's/\(.*\):\(.*\)/\2/')"
    if [ ${osd_id} = ${1} ]; then
      echo -n "${osd_dev}"
    fi
  done
}

function non_supported_scenario_on_redhat {
  if [[ -f /etc/redhat-release ]]; then
    if grep -sq "Red Hat Enterprise Linux Server" /etc/redhat-release; then
      echo "ERROR: scenario not supported by this distribution"
      echo "Valid scenarios for RHEL are: ... ... ..."
      exit 1
    fi
  fi
}
