Ceph Kubernetes Secret Generation
=================================

This script will generate ceph keyrings and configs as Kubernetes secrets.

Sigil is required for template handling and must be installed in system PATH. Instructions can be found here: https://github.com/gliderlabs/sigil

The following functions are provided:

## Generate raw FSID (can be used for other functions)

`./generate_secrets.sh fsid`

## Generate raw ceph.conf (For verification)

`./generate_secrets.sh ceph-conf-raw <fsid> "overridekey=value"`

Take a look at `ceph/ceph.conf.tmpl` for the default values

## Generate encoded ceph.conf secret

`./generate_secrets.sh ceph-conf <fsid> "overridekey=value"`

## Generate encoded admin keyring secret

`./generate_secrets.sh admin-keyring`

## Generate encoded mon keyring secret

`./generate_secrets.sh mon-keyring`

## Generate a combined secret

Contains ceph.conf, admin keyring and mon keyring. Useful for generating the `/etc/ceph` directory

`./generate_secrets.sh combined-conf`

## Generate encoded boostrap keyring secret

`./generate_secrets.sh bootstrap-keyring <osd|mds|rgw>`

Kubernetes workflow
===================

```
./generate_secrets.sh combined-conf `./generate_secrets.sh fsid` > combined.yaml
./generate_secrets.sh bootstrap-keyring osd > bootstrap-osd.yaml
./generate_secrets.sh bootstrap-keyring mds > bootstrap-mds.yaml
./generate_secrets.sh bootstrap-keyring rgw > bootstrap-rgw.yaml

kubectl create -f combined.yaml --namespace=ceph
kubectl create -f bootstrap-osd.yaml --namespace=ceph
kubectl create -f bootstrap-mds.yaml --namespace=ceph
kubectl create -f bootstrap-rgw.yaml --namespace=ceph
kubectl create secret generic ceph-client-key --from-file=ceph-client-key --namespace=ceph

```
