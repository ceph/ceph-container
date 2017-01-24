# Ceph on Kubernetes

This Guide will take you through the process of deploying a Ceph cluster on to a Kubernetes cluster.

## WARNING

This example does not survive Kubernetes cluster restart! The Monitors need persistent storage. This is not covered here.

## Client Requirements

In addition to kubectl, Sigil is required for template handling and must be installed in your system PATH. Instructions can be found here: <https://github.com/gliderlabs/sigil>

## Cluster Requirements

At a High level:

- The Kubernetes SkyDNS addon needs to be set as a resolver on masters and nodes
- Ceph and RBD utilities must be installed on masters and nodes
- Linux Kernel should be newer than 4.2.0

### SkyDNS Resolution

The Ceph MONs are what clients talk to when mounting Ceph storage. Because Ceph MON IPs can change, we need a Kubernetes service to front them. Otherwise your clients will eventually stop working over time as MONs are rescheduled.

To get skyDNS resolution working, the resolv.conf on your nodes should look something like this:

```
domain <EXISTING_DOMAIN>
search <EXISTING_DOMAIN>

search svc.cluster.local #Your kubernetes cluster ip domain

nameserver 10.0.0.10     #The cluster IP of skyDNS
nameserver <EXISTING_RESOLVER_IP>
```

### Ceph and RBD utilities installed on the nodes

The Kubernetes kubelet shells out to system utilities to mount Ceph volumes. This means that every system must have these utilities installed. This requirement extends to the control plane, since there may be interactions between kube-controller-manager and the Ceph cluster.

For Debian-based distros:

```
apt-get install ceph-fs-common ceph-common
```

For Redhat-based distros:

```
yum install ceph
```

### Linux Kernel version 4.2.0 or newer

You'll need a newer kernel to use this. Kernel panics have been observed on older versions. Your kernel should also have RBD support.

This has been tested on:

- Ubuntu 15.10

This will not work on:

- Debian 8.5

## Quickstart

If you're feeling confident:

```
./create_ceph_cluster.sh
kubectl create -f ceph-cephfs-test.yaml --namespace=ceph
kubectl get all --namespace=ceph
```

This will most likely not work on your setup, see the rest of the guide if you encounter errors.

We will be working on making this setup more agnostic, especially in regards to the network IP ranges.

## Tutorial

### Override the default network settings

By default, `10.244.0.0/16` is used for the `cluster_network` and `public_network` in ceph.conf. To change these defaults, set the following environment variables according to your network requirements. These IPs should be set according to the range of your Pod IPs in your kubernetes cluster:

```
export osd_cluster_network=192.168.0.0/16
export osd_public_network=192.168.0.0/16
```

These will be picked up by sigil when generating the kubernetes secrets in the next section.

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

Please note that you should save the output files of this command, future invocations of scripts will overwrite existing keys and configuration. If you lose these files they can still be retrieved from Kubernetes via `kubectl get secret`.

### Deploy Ceph Components

With the secrets created, you can now deploy ceph.

```
kubectl create \
-f ceph-mds-v1-dp.yaml \
-f ceph-mon-v1-svc.yaml \
-f ceph-mon-v1-dp.yaml \
-f ceph-mon-check-v1-dp.yaml \
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
kubectl label node <nodename> node-type=storage
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

Now, if skyDNS is set as a resolver for your host nodes then execute the below command as is. Otherwise modify the `ceph-mon.ceph` host to match the IP address of one of your ceph-mon pods.

```
kubectl create -f ceph-cephfs-test.yaml --namespace=ceph
```

You should be able to see the filesystem mounted now

```
kubectl exec -it --namespace=ceph ceph-cephfs-test df
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

#### Durable Storage

By default `emptyDir` is used for everything. If you have durable storage on your nodes, replace the emptyDirs with a `hostPath` to that storage.

#### Enabling Jewel RBD features

We disable new RBD features by default since most operating systems cannot mount volumes using these features. You can override this by setting the following before running sigil or the convenience scripts.

```
export client_rbd_default_features=61
```

If you have older nodes in your cluster that may need to mount a volume that has been created with these newer features, you must remove the features from the volume by running these commands from a Ceph pod:

```
rbd feature disable <VOLUME NAME> fast-diff
rbd feature disable <VOLUME NAME> deep-flatten
rbd feature disable <VOLUME NAME> object-map
rbd feature disable <VOLUME NAME> exclusive-lock
```
