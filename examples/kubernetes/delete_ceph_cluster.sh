#!/bin/bash

kubectl delete secret ceph-secret-admin --namespace kube-system
kubectl get pv | grep 'ceph/' | awk {'print $1'} | xargs -I{} kubectl delete pv {}
kubectl delete storageclass slow
kubectl delete namespace ceph
kubectl label nodes --all node-type-
