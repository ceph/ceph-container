#!/bin/bash

kubectl create -f ceph-mon-v1-ds.yaml
sleep 240
kubectl create -f ceph-osd-v1-pod.yaml
kubectl create -f ceph-mon-check-v1-rc.yaml

