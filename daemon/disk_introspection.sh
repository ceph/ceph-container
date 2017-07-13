#!/bin/bash
set -e

HOSTNAME=$(uname -n)
MY_NAMESPACE=$(kubectl get pods --all-namespaces -o jsonpath="{.items[?(@.metadata.name == \"${HOSTNAME}\")].metadata.namespace}")
DISK_FILE=$(kubectl --namespace="${MY_NAMESPACE}" get pods "${HOSTNAME}" -o jsonpath="{.spec.nodeName}")-disks
DISK_FILE_PATH=/tmp/$DISK_FILE

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
  DISCOVERED_DEVICES=$(lsblk --output NAME --noheadings --raw --scsi)
}

function get_all_disks_without_partitions {
  for disk in $DISCOVERED_DEVICES; do
    if [[ "$(grep -Ec "${disk}[0-9]" /proc/partitions)" == 0 ]]; then
      echo "/dev/$disk" >> "$DISK_FILE_PATH"
    fi
  done
  if [ ! -s "$DISK_FILE_PATH" ]; then
    log "No disk detected."
    log "Abort mission!"
    exit 1
  fi
}

function store_disk_list_configmaps {
  log "Creating configmap $DISK_FILE in the 'ceph' namespace"
  kubectl --namespace="$MY_NAMESPACE" create configmap "$DISK_FILE" --from-file="$DISK_FILE_PATH"
  log "Here is/are the device(s) I discovered: $DISCOVERED_DEVICES"
}

ami_privileged
get_all_disks_without_partitions
store_disk_list_configmaps
