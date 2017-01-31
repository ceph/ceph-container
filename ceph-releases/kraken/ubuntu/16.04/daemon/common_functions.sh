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

# create socket directory
function create_socket_dir {
  mkdir -p /var/run/ceph
  chown ceph. /var/run/ceph
}

# Calculate proper device names, given a device and partition number
function dev_part {
  if [[ -L ${1} ]]; then
    # This device is a symlink. Work out it's actual device
    local actual_device=$(readlink -f ${1})
    local bn=$(basename $1)
    if [[ "${ACTUAL_DEVICE:0-1:1}" == [0-9] ]]; then
      local desired_partition="${actual_device}p${2}"
    else
      local desired_partition="${actual_device}${2}"
    fi
    # Now search for a symlink in the directory of $1
    # that has the correct desired partition, and the longest
    # shared prefix with the original symlink
    local symdir=$(dirname $1)
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
      >&2 log "Could not locate appropriate symlink for partition $2 of $1"
      exit 1
    fi
    echo "$link"
  elif [[ "${1:0-1:1}" == [0-9] ]]; then
    echo "${1}p${2}"
  else
    echo "${1}${2}"
  fi
}

function osd_trying_to_determine_scenario {
  if [ -z "${OSD_DEVICE}" ]; then
    log "Bootstrapped OSD(s) found; using OSD directory"
    osd_directory
  elif $(parted --script ${OSD_DEVICE} print | egrep -sq '^ 1.*ceph data'); then
    log "Bootstrapped OSD found; activating ${OSD_DEVICE}"
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
