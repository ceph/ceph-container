#!/bin/bash

kubectl delete -f ceph-mon-v1-ds.yaml
kubectl delete -f ceph-osd-v1-pod.yaml
kubectl delete -f ceph-mon-check-v1-rc.yaml

