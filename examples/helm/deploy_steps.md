
# Unless already in place, build k8s cluster
Can be done using kubeadm, by using: https://github.com/ReSearchITEng/kubeadm-playbook

# Only once, run this setup:
```bash
git clone https://github.com/ReSearchITEng/ceph-docker #This one has some fixes which were not yet merged in origin
helm serve &
helm repo add marina http://127.0.0.1:8879/charts
#Label the nodes that will take part in the Ceph cluster
kubectl get nodes -L kubeadm.alpha.kubernetes.io/role --no-headers | awk '$NF ~ /^<none>/ { print $1}' | while read NODE ; do
  kubectl label node $NODE --overwrite ceph-storage=enabled
done
```

# Every time you make a change to the helm chart, rebuild it and retest it with this script:
```bash
PatchV=${PatchV:-2}
hfV=${hfV:-1}
cd ceph-docker/examples/helm/
helm delete $(helm list | grep ceph | awk '{print $1}' )
echo "going to remove ceph namespace to ensure secrets are removed also(, or remove them manually)"
kubectl delete namespace ceph #to ensure secrets are removed also, or remove them manually
while [[ $(kubectl get ns | grep -w -c 'ceph' || true ) -gt 1 ]]; do sleep 1; done
echo "cleaning up ceph folder on the nodes (rm -rf /var/lib/ceph-helm ). If you are ok with it, hit enter now"
sleep 2 #give user a chance to cancel it :)
for node in $(kubectl get nodes | grep Ready | cut -f1 -d" ") 
do 
  echo "Running: ssh root@$node rm -rf /var/lib/ceph-helm"
  ssh root@$node 'hostname; rm -rf /var/lib/ceph-helm'
done
set -e
set -o pipefail
kubectl create namespace ceph; 
(( hfV++ ))
echo "Going to create new helm package version: 0.${PatchV}.${hfV}"
echo "pack&deploy hfV=$hfV" 
helm package --version 0.${PatchV}.${hfV} ceph
helm repo update
helm install --namespace ceph marina/ceph --version 0.${PatchV}.${hfV} --set network.cluster='10.244.0.0/16',network.public='10.244.0.0/16',images.daemon=docker.io/ceph/daemon:build-main-mimic-centos-7
set +e
```
Note: when flanned is used, the network should be set to: '10.244.0.0/16'. If it's calico or something else, put values accordingly.

# ceph docker images tags one may want to test:
tag-build-master-luminous-centos-7 (new image)   
tag-build-master-mimic-centos-7 (new image)    
