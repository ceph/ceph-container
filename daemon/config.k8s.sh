#!/bin/bash
set -e

function get_admin_key {
   # No-op for static
   log "k8s: does not generate the admin key. Use Kubernetes secrets instead."
}

function get_mon_config {
  # Get fsid from ceph.conf
  local fsid=$(ceph-conf --lookup fsid -c /etc/ceph/${CLUSTER}.conf)

  timeout=10
  MONMAP_ADD=""

  while [[ -z "${MONMAP_ADD// }" && "${timeout}" -gt 0 ]]; do
    # Get the ceph mon pods (name and IP) from the Kubernetes API. Formatted as a set of monmap params
    if [[ ${K8S_HOST_NETWORK} -eq 0 ]]; then
        MONMAP_ADD=$(kubectl get pods --namespace=${CLUSTER} -l daemon=mon -o template --template="{{range .items}}{{if .status.podIP}}--add {{.metadata.name}} {{.status.podIP}} {{end}} {{end}}")
    else
        MONMAP_ADD=$(kubectl get pods --namespace=${CLUSTER} -l daemon=mon -o template --template="{{range .items}}{{if .status.podIP}}--add {{.spec.nodeName}} {{.status.podIP}} {{end}} {{end}}")
    fi
    (( timeout-- ))
    sleep 1
  done

  if [[ -z "${MONMAP_ADD// }" ]]; then
      exit 1
  fi

  # Create a monmap with the Pod Names and IP
  monmaptool --create ${MONMAP_ADD} --fsid ${fsid} $MONMAP

}

function get_config {
   # No-op for static
   log "k8s: config is stored as k8s secrets."
}
