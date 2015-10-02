#!/bin/bash
set -e

function get_admin_key {
   # No-op for static
   echo "k8s: does not generate admin key. Use secrets instead."
}

function get_mon_config {
  
  MONMAP_ADD=$(kubectl get pods --namespace=${CLUSTER} -l daemon=mon -o template --template="{{range .items}}--add {{.metadata.name}} {{.status.podIP}} {{end}}")
  # MONMAP_ADD="${HOSTS%?}"

  monmaptool --create ${MONMAP_ADD} --fsid ${FSID} /etc/ceph/monmap

  # Update hostname in ceph.conf
  sed -i "s/HOSTNAME/${MON_NAME}/g" /etc/ceph/ceph.conf
  # sed -i "s/\[\[CEPH_PUBLIC_NETWORK\]\]/${CEPH_PUBLIC_NETWORK}/g" /etc/ceph/ceph.conf
  # sed -i "s/[[CEPH_CLUSTER_NETWORK]]/${CEPH_CLUSTER_NETWORK}/g" /etc/ceph/ceph.conf

}

function get_config {
   # No-op for static
   echo "k8s: does not generate config. Use secrets instead."
}

