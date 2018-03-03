# Ceph RBD Provisioner

We use the dynamic RBD provisioner plugin. The manifests are based on
the example from [1], the storage class is based on [2].
When setting up the cluster using kubeadm, thus having a self-hosted
setup where the API server runs as a pod itself, the in-tree provisioner
may no longer be used as the controller images are lacking the required
Ceph tools.

OpenShift has a good documentation on how to setup the RBD pool [3].
Note that we use the 'ceph' namespace for everything, infrastructure
(see parent directory), provisioner, and secrets.
I have used the following, slightly adapted, commands:

```
ceph osd pool create kube 64
ceph auth get-or-create client.kube mon 'allow r' osd \
  'allow class-read object_prefix rbd_children, allow rwx pool=kube' \
  -o ceph.client.kube.keyring
kubectl --namespace=ceph create secret generic ceph-rbd-kube \
  --from-literal="key=$(grep key ceph.client.kube.keyring  | awk '{ print $3 }')" \
  --type=kubernetes.io/rbd
```

Our current provisioner image is based on [4]. (you can also build the current
image yourself, however, that failed with missing Go dependencies on the multi-stage
release build). This should be remedied later when the actual image [5] is finally
updated [6].

Note that the node hosts still need to have the Ceph RBD tools available
(on Fedora or CentOS install ceph-common).

[1] https://github.com/kubernetes-incubator/external-storage/tree/master/ceph/rbd/deploy/rbac
[2] https://github.com/kubernetes-incubator/external-storage/blob/master/ceph/rbd/examples/class.yaml
[3] https://docs.openshift.org/3.6/install_config/storage_examples/ceph_rbd_dynamic_example.html
[4] https://hub.docker.com/r/anatolyrugalev/rbd-provisioner/
[5] https://quay.io/repository/external_storage/rbd-provisioner
[6] https://github.com/kubernetes-incubator/external-storage/issues/608

