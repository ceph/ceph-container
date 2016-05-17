#!/bin/bash

kubectl create \
-f ceph-mds-v1-rc.yaml \
-f ceph-mon-v1-svc.yaml \
-f ceph-mon-v1-ds.yaml \
-f ceph-mon-check-v1-rc.yaml \
-f ceph-osd-v1-ds.yaml \
--namespace=ceph
