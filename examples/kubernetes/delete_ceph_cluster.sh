#!/bin/bash

kubectl delete namespace ceph
kubectl delete secret ceph-secret-admin --namespace kube-system
kubectl delete storageclass slow
kubectl delete pv --all
kubectl label nodes --all node-type-
