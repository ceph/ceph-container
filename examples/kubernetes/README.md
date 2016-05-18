Ceph on Kubernetes
=====
This Guide will take you through the process of deploying a Ceph cluster on to a Kubernetes cluster.

Sigil is required for template handling and must be installed in system PATH. Instructions can be found here: [https://github.com/gliderlabs/sigil](https://github.com/gliderlabs/sigil)

# Quickstart

If you're feeling confident:

```
./create_ceph_cluster.sh
kubectl create -f ceph-cephfs-test.yaml --namespace=ceph
kubectl get all --namespace=ceph
```

This will most likely not work on your setup, see the rest of the guide if you encounter errors.

We will be working on making this setup more agnostic, especially in regards to the network IP ranges.

# Tutorial

### Generate keys and configuration

Run the following commands to generate the required configuration and keys.

```
cd generator
./generate_secrets.sh all `./generate_secrets.sh fsid`

kubectl create namespace ceph

kubectl create secret generic ceph-conf-combined --from-file=ceph.conf --from-file=ceph.client.admin.keyring --from-file=ceph.mon.keyring --namespace=ceph
kubectl create secret generic ceph-bootstrap-rgw-keyring --from-file=ceph.keyring=ceph.rgw.keyring --namespace=ceph
kubectl create secret generic ceph-bootstrap-mds-keyring --from-file=ceph.keyring=ceph.mds.keyring --namespace=ceph
kubectl create secret generic ceph-bootstrap-osd-keyring --from-file=ceph.keyring=ceph.osd.keyring --namespace=ceph
kubectl create secret generic ceph-client-key --from-file=ceph-client-key --namespace=ceph

cd ..
```

Please note that you should save the output files of this command, they will overwrite existing keys and configuration. If you lose these files they can still be retrieved from Kubernetes via `kubectl get secret`.

### Deploy Ceph Components

With the secrets created, you can now deploy ceph.

```
kubectl create \
-f ceph-mds-v1-rc.yaml \
-f ceph-mon-v1-svc.yaml \
-f ceph-mon-v1-ds.yaml \
-f ceph-mon-check-v1-rc.yaml \
-f ceph-osd-v1-ds.yaml \
--namespace=ceph
```

Your cluster should now look something like this.

```
$ kubectl get all --namespace=ceph
NAME                   DESIRED      CURRENT       AGE
ceph-mds               1            1             24s
ceph-mon-check         1            1             24s
NAME                   CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
ceph-mon               None         <none>        6789/TCP   24s
NAME                   READY        STATUS        RESTARTS   AGE
ceph-mds-6kz0n         0/1          Pending       0          24s
ceph-mon-check-deek9   1/1          Running       0          24s
```

### Label your storage nodes

You must label your storage nodes in order to run Ceph pods on them.

```
kubectl label node <nodename> node-type-storage
```

If you want all nodes in your Kubernetes cluster to be a part of your Ceph cluster, label them all.

```
kubectl label nodes node-type=storage --all
```

Eventually all pods will be running, including a mon and osd per every labeled node.

```
$ kubectl get pods --namespace=ceph
NAME                   READY     STATUS    RESTARTS   AGE
ceph-mds-6kz0n         1/1       Running   0          4m
ceph-mon-8wxmd         1/1       Running   2          2m
ceph-mon-c8pd0         1/1       Running   1          2m
ceph-mon-cbno2         1/1       Running   1          2m
ceph-mon-check-deek9   1/1       Running   0          4m
ceph-mon-f9yvj         1/1       Running   1          2m
ceph-osd-3zljh         1/1       Running   2          2m
ceph-osd-d44er         1/1       Running   2          2m
ceph-osd-ieio7         1/1       Running   2          2m
ceph-osd-j1gyd         1/1       Running   2          2m
```

### Mounting CephFS in a pod

First you must add the admin client key to your current namespace (or the namespace of your pod).

```
kubectl create secret generic ceph-client-key --from-file=./generator/ceph-client-key
```

Now, if skyDNS is set as a resolver for your host nodes:

```
kubectl create -f ceph-cephfs-test.yaml --namespace=ceph
```

You should be able to see the filesystem mounted now

```
kubectl exec -it --namespace=ceph ceph-cephfs-test df
```

Otherwise you must edit the file and replace `ceph-mon.ceph` with a Pod IP. It is highly reccomended that you place skyDNS as a resolver, otherwise your configuration WILL eventually stop working as Mons are rescheduled.

To get skyDNS resolution working, your resolv.conf should look something like this:

```
domain <EXISTING_DOMAIN>
search <EXISTING_DOMAIN>

search svc.cluster.local

nameserver 10.0.0.10
nameserver <EXISTING_RESOLVER_IP>
```

If your pod has issues mounting, make sure mount.ceph is installed on all nodes.

For Debian-based distros:

```
apt-get install ceph-fs-common ceph-common
```

For Redhat:

```
yum install ceph
```

### Mounting a Ceph RBD in a pod

First we have to create an RBD volume.

```
# This gets a random MON pod.
export PODNAME=`kubectl get pods --selector="app=ceph,daemon=mon" --output=template --template="{{with index .items 0}}{{.metadata.name}}{{end}}" --namespace=ceph`

kubectl exec -it $PODNAME --namespace=ceph -- rbd create ceph-rbd-test --size 20G

kubectl exec -it $PODNAME --namespace=ceph -- rbd info ceph-rbd-test
```

The same caveats apply for RBDs as Ceph FS volumes. Edit the pod accordingly. Once you're set:

```
kubectl create -f ceph-rbd-test.yaml --namespace=ceph
```

And again you should see your mount, but with 20 gigs free

```
kubectl exec -it --namespace=ceph ceph-rbd-test -- df -h
```


### Common Modifications

By default `emptyDir` is used for everything. If you have durable storage on your nodes, replace the emptyDirs with a `hostPath` to that storage.

Also, 10.244.0.0/16 is used for the default network settings, change these in the Kubernetes yaml objects and the sigil templates to reflect your network.