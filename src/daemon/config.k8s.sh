#!/bin/bash

set -e

function get_admin_key {
   # No-op for static
   log "k8s: does not generate the admin key. Use Kubernetes secrets instead."
}

function get_mon_config {
  # Get fsid from ceph.conf
  local fsid
  fsid=$(ceph-conf --lookup fsid -c /etc/ceph/"${CLUSTER}".conf)

  local timeout=10
  local monmap_add=""
  while [[ -z "${monmap_add// }" && "${timeout}" -gt 0 ]]; do
    # Get the ceph mon pods (name and IP) from the Kubernetes API. Formatted as a set of monmap params
    if [[ ${K8S_HOST_NETWORK} -eq 0 ]]; then
      monmap_add=$(kubectl get pods --selector="${K8S_MON_SELECTOR}" -o template --template="{{range .items}}{{if .status.podIP}}--add {{.metadata.name}} {{.status.podIP}}:6789 {{end}} {{end}}")
    else
      monmap_add=$(kubectl get pods --selector="${K8S_MON_SELECTOR}" -o template --template="{{range .items}}{{if .status.podIP}}--add {{.spec.nodeName}} {{.status.podIP}}:6789 {{end}} {{end}}")
    fi
    (( timeout-- ))
    sleep 1
  done
  IFS=" " read -r -a monmap_add_array <<< "${monmap_add}"

  if [[ -z "${monmap_add// }" ]]; then
    log "No Ceph Monitor pods discovered. Abort mission!"
    exit 1
  fi

  # Create a monmap with the Pod Names and IP
  monmaptool --create "${monmap_add_array[@]}" --fsid "${fsid}" "$MONMAP"

}

function get_config {
   # No-op for static
   log "k8s: config is stored as k8s secrets."
}
