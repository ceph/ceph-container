#!/bin/bash

kubectl delete secret ceph-secret-admin --namespace kube-system
kubectl delete storageclass slow
kubectl delete pv --all -n ceph
kubectl delete namespace ceph
kubectl label nodes --all node-type-
