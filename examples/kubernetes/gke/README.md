# Ceph on GKE Kubernetes cluster

This Guide will take you through the process of deploying a Ceph cluster on to a GKE Kubernetes cluster.

## Client Requirements

In addition to `kubectl`, `jinja2` or `sigil` is required for template handling and must be installed in your system PATH. Instructions can be found here
for `jinja2` <https://github.com/mattrobenolt/jinja2-cli> or here for `sigil` <https://github.com/gliderlabs/sigil>.

## Cluster Requirements

At a High level:

- Google Cloud Platform account with a project created to work under.
- At least 20 virtual CPUs available in your zone. If you do not have at least 20 virtual CPUs, you'll have to decrease the number of pods, CPU requests and limit amounts for deployments, and/or adjust the default placement group numbers so that we have the right amount of placement groups per OSD (300) ratio.
- Ceph and RBD utilities must be installed on Ceph client nodes (more later).

## Set up a GKE Kubernetes container cluster with 10 nodes

### Set up gcloud configuration

Before proceeding make sure you have a Google Cloud Platform project umbrella to work under and the correct `gcloud` configuration setup so that any subsequent commands you run will default to the correct project, zone, etc. This can easily be done by running the `gcloud init` command. See [https://cloud.google.com/sdk/docs/initializing](https://cloud.google.com/sdk/docs/initializing) for more details. Here's an example of what it should look like to match the commands in the rest of this demo:

```
→ gcloud config list
Your active configuration is: [default]

[compute]
region = us-west1
zone = us-west1-a
[core]
account = you@example.com
project = kube-ceph-cluster
```
If it doesn't match this, then make sure you make the appropriate changes in the `gcloud container create` command below. Otherwise, run `gcloud init` or the commands below to set it up correctly:

```
→ gcloud config configurations activate default
→ gcloud config set compute/region us-west1
Updated property [compute/region].
→ gcloud config set compute/zone us-west1-a
Updated property [compute/zone].
→ gcloud config set core/account you@example.com
Updated property [core/account].
→ gcloud config set project kube-ceph-cluster
Updated property [core/project].
```

### Create GKE Kubernetes container cluster

Now we need to set up a GKE Kubernetes container cluster. We will start with 10 nodes: 3 ceph-mon nodes and 7 storage nodes to run the Ceph storage cluster i.e. OSDs, MDSs, and RGWs. We can later add another client node to facilitate testing.

Google Container Engine provides the ability to specify what version of Kubernetes you would like to use by passing the `--cluster-version` option. See the [GKE release notes](https://cloud.google.com/container-engine/release-notes) for more information.

Let's start by creating our container cluster using the below command. Adjust the options to your specific use case if necessary.

```
→ gcloud container --project "kube-ceph-cluster" clusters create --cluster-version=1.5.1 "kube-ceph-cluster" --zone "us-west1-a" --machine-type "n1-standard-2" --image-type "GCI" --disk-size "100" --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "10" --network "default" --enable-cloud-logging --no-enable-cloud-monitoring
Creating cluster kube-ceph-cluster...done.
Created [https://container.googleapis.com/v1/projects/kube-ceph-cluster/zones/us-west1-a/clusters/kube-ceph-cluster].
kubeconfig entry generated for kube-ceph-cluster.
NAME               ZONE        MASTER_VERSION  MASTER_IP        MACHINE_TYPE   NODE_VERSION  NUM_NODES  STATUS
kube-ceph-cluster  us-west1-a  1.5.1           104.196.238.226  n1-standard-2  1.5.1         10         RUNNING
```

Then configure `kubectl` on your local machine to access the cluster. If you don't have `kubectl` installed, then install it with `gcloud components install kubectl` or download the right binary version of it to match the version of Kubernetes on the cluster. See [http://kubernetes.io/docs/getting-started-guides/kubectl/](http://kubernetes.io/docs/getting-started-guides/kubectl/) for more details. Once `kubectl` is installed, configure it to access the cluster and check the version:

```
→ gcloud container clusters get-credentials kube-ceph-cluster
Fetching cluster endpoint and auth data.
kubeconfig entry generated for kube-ceph-cluster.
→ kubectl version
Client Version: version.Info{Major:"1", Minor:"5", GitVersion:"v1.5.1", GitCommit:"82450d03cb057bab0950214ef122b67c83fb11df", GitTreeState:"clean", BuildDate:"2016-12-14T00:57:05Z", GoVersion:"go1.7.4", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"5", GitVersion:"v1.5.1", GitCommit:"82450d03cb057bab0950214ef122b67c83fb11df", GitTreeState:"clean", BuildDate:"2016-12-14T00:52:01Z", GoVersion:"go1.7.4", Compiler:"gc", Platform:"linux/amd64"}
```

Verify the container cluster nodes are ready:

```
→ kubectl get nodes
NAME                                               STATUS    AGE
gke-kube-ceph-cluster-default-pool-592ab398-5dhc   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-5hr0   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-6t50   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-9kqn   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-dthr   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-g9qs   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-qfzk   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-w226   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-x9nx   Ready     15m
gke-kube-ceph-cluster-default-pool-592ab398-zt57   Ready     15m
```

### Create a clone of this repository in your work space

```
git clone https://github.com/ceph/ceph-container.git
cd ceph-container/examples/kubernetes
```

### Override default settings

These will be picked up by `jinja2` or `sigil` when generating the Kubernetes secrets in the next section.

#### Override the default network settings

By default, `10.244.0.0/16` is used for the `cluster_network` and `public_network` in the generated ceph.conf. To change these defaults, set the following environment variables according to your GKE network requirements. These IPs should be set according to the range of your Pod IPs in your Kubernetes cluster:

```
→ GKE_NETWORK=$(gcloud container clusters describe kube-ceph-cluster | awk '/clusterIpv4/ { print $2 }')
→ export osd_cluster_network=${GKE_NETWORK}
→ export osd_public_network=${GKE_NETWORK}
→ printenv | grep network
osd_cluster_network=10.0.0.0/14
osd_public_network=10.0.0.0/14
```

#### Override the default number of placement groups

By default, 128 is used for the `osd_pool_default_pg_num` and `osd_pool_default_pgp_num` in the generated ceph.conf. That's because the recommended number of placement groups per pool for less than 5 OSDs is 128. This means that we would need to increase the number of OSDs to maintain a healthy placement group to OSD ratio (300) when using a default pool replication size of 3 set by `osd_pool_default_size`. However, we have a default limit of 24 virtual CPUs provided by the Google Cloud Platform without requesting an increase in CPU quota. Therefore, we will have to reduce the default number of placement groups in order to achieve a Ceph cluster `HEALTH_OK` status using the same number of OSDs to stay within our CPU quota limit. This is okay for demonstration purposes but is not recommended for production. See [http://docs.ceph.com/docs/main/rados/operations/placement-groups/](http://docs.ceph.com/docs/main/rados/operations/placement-groups/) for more information.

Let's go ahead and reduce the default number of placement groups from 128 down to 64:

```
export global_osd_pool_default_pg_num=64
export global_osd_pool_default_pgp_num=64
```

### Generate Ceph Kubernetes keys and configuration

Run the following command to generate the required configuration and keys. This will also create a Kubernetes `ceph` namespace, then create secrets in that namespace using the generated configuration and keys.

```
./create_secrets.sh
```

Please note that you should save the output files of this command. Future invocations of scripts will overwrite existing keys and configuration. If you lose these files they can still be retrieved from Kubernetes via `kubectl get secret`.

### Configure kubectl to use the ceph namespace in current GKE context

After setting the current context's namespace, all subsequent comands will default to the `ceph` namespace. So let's do that now:

```
→ kubectl config set-context gke_kube-ceph-cluster_us-west1-a_kube-ceph-cluster --namespace ceph
Context "gke_kube-ceph-cluster_us-west1-a_kube-ceph-cluster" set.
```

### Deploy Ceph Components

With the secrets created, you can now deploy Ceph.

#### Deploy Ceph Monitor Components

Create the Ceph Monitor deployment and service components:

```
→ kubectl create -f ceph-mon-v1-svc.yaml -f ceph-mon-v1-dp.yaml
service "ceph-mon" created
deployment "ceph-mon" created
→ kubectl get pods -o wide --watch
NAME                        READY     STATUS              RESTARTS   AGE       IP        NODE
ceph-mon-2416973846-00glw   0/1       ContainerCreating   0          6s        <none>    gke-kube-ceph-cluster-default-pool-592ab398-x9nx
ceph-mon-2416973846-5rks2   0/1       ContainerCreating   0          6s        <none>    gke-kube-ceph-cluster-default-pool-592ab398-5dhc
ceph-mon-2416973846-vns3q   0/1       ContainerCreating   0          6s        <none>    gke-kube-ceph-cluster-default-pool-592ab398-9kqn
NAME                        READY     STATUS    RESTARTS   AGE       IP         NODE
ceph-mon-2416973846-5rks2   0/1       Running   0          30s       10.0.1.3   gke-kube-ceph-cluster-default-pool-592ab398-5dhc
ceph-mon-2416973846-00glw   0/1       Running   0         30s       10.0.3.3   gke-kube-ceph-cluster-default-pool-592ab398-x9nx
ceph-mon-2416973846-vns3q   0/1       Running   0         33s       10.0.2.3   gke-kube-ceph-cluster-default-pool-592ab398-9kqn
ceph-mon-2416973846-5rks2   1/1       Running   0         40s       10.0.1.3   gke-kube-ceph-cluster-default-pool-592ab398-5dhc
ceph-mon-2416973846-vns3q   1/1       Running   0         40s       10.0.2.3   gke-kube-ceph-cluster-default-pool-592ab398-9kqn
ceph-mon-2416973846-00glw   1/1       Running   0         40s       10.0.3.3   gke-kube-ceph-cluster-default-pool-592ab398-x9nx
```

Your cluster should now look something like this:

```
→ kubectl get all -o wide
NAME                           READY     STATUS    RESTARTS   AGE       IP         NODE
po/ceph-mon-2416973846-00glw   1/1       Running   0          1m        10.0.3.3   gke-kube-ceph-cluster-default-pool-592ab398-x9nx
po/ceph-mon-2416973846-5rks2   1/1       Running   0          1m        10.0.1.3   gke-kube-ceph-cluster-default-pool-592ab398-5dhc
po/ceph-mon-2416973846-vns3q   1/1       Running   0          1m        10.0.2.3   gke-kube-ceph-cluster-default-pool-592ab398-9kqn

NAME           CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE       SELECTOR
svc/ceph-mon   None         <none>        6789/TCP   1m        app=ceph,daemon=mon

NAME              DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/ceph-mon   3         3         3            3           1m

NAME                     DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)             SELECTOR
rs/ceph-mon-2416973846   3         3         3         1m        ceph-mon       ceph/daemon:latest   app=ceph,daemon=mon,pod-template-hash=2416973846
```

#### Deploy Ceph OSD Components

```
→ kubectl create -f ceph-osd-v1-ds.yaml
daemonset "ceph-osd" created
```

#### Deploy Ceph MDS Component

```
→ kubectl create -f ceph-mds-v1-dp.yaml
deployment "ceph-mds" created
```

#### Deploy Ceph RGW Component

```
→ kubectl create -f ceph-rgw-v1-svc.yaml -f ceph-rgw-v1-dp.yaml
service "ceph-rgw" created
deployment "ceph-rgw" created
```

### Label your storage nodes

You must label your storage nodes in order to run other Ceph daemon pods on them. You can label as many nodes as you want OSDs, MDSs, and RGWs to run on as long as there are enough resources on that node. If you want all nodes, including the ones running Ceph monitor pods, in your Kubernetes cluster to be eligible to run Ceph OSDs, MDSs, and RGWs, label them all.

```
kubectl label nodes node-type=storage --all
```
For this particular example, we'll just choose the remaining 7 nodes that are not currently running Ceph Monitor pods.

```
→ kubectl get pods -o wide
NAME                        READY     STATUS    RESTARTS   AGE       IP         NODE
ceph-mds-2743106415-n3cp3   0/1       Pending   0          21s       <none>
ceph-mon-2416973846-00glw   1/1       Running   0          3m        10.0.3.3   gke-kube-ceph-cluster-default-pool-592ab398-x9nx
ceph-mon-2416973846-5rks2   1/1       Running   0          3m        10.0.1.3   gke-kube-ceph-cluster-default-pool-592ab398-5dhc
ceph-mon-2416973846-vns3q   1/1       Running   0          3m        10.0.2.3   gke-kube-ceph-cluster-default-pool-592ab398-9kqn
ceph-rgw-384278267-j38r0    0/1       Pending   0          14s       <none>
ceph-rgw-384278267-vcbrm    0/1       Pending   0          14s       <none>
ceph-rgw-384278267-zxqs6    0/1       Pending   0          14s       <none>
→ kubectl get nodes
NAME                                               STATUS    AGE
gke-kube-ceph-cluster-default-pool-592ab398-5dhc   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-5hr0   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-6t50   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-9kqn   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-dthr   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-g9qs   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-qfzk   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-w226   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-x9nx   Ready     27m
gke-kube-ceph-cluster-default-pool-592ab398-zt57   Ready     27m
→ MON_NODES=$(kubectl get pods -o wide | awk '/ceph-mon/ {print $7}')
→ echo ${MON_NODES}
gke-kube-ceph-cluster-default-pool-592ab398-x9nx gke-kube-ceph-cluster-default-pool-592ab398-5dhc gke-kube-ceph-cluster-default-pool-592ab398-9kqn
→ UNUSED_NODES=$(kubectl get nodes | grep -v "${MON_NODES}" | awk '/Ready/ {print $1}')
→ echo ${UNUSED_NODES}
gke-kube-ceph-cluster-default-pool-592ab398-5hr0 gke-kube-ceph-cluster-default-pool-592ab398-6t50 gke-kube-ceph-cluster-default-pool-592ab398-dthr gke-kube-ceph-cluster-default-pool-592ab398-g9qs gke-kube-ceph-cluster-default-pool-592ab398-qfzk gke-kube-ceph-cluster-default-pool-592ab398-w226 gke-kube-ceph-cluster-default-pool-592ab398-zt57
→ for i in ${UNUSED_NODES}; do kubectl label node ${i} node-type=storage; done
node "gke-kube-ceph-cluster-default-pool-592ab398-5hr0" labeled
node "gke-kube-ceph-cluster-default-pool-592ab398-6t50" labeled
node "gke-kube-ceph-cluster-default-pool-592ab398-dthr" labeled
node "gke-kube-ceph-cluster-default-pool-592ab398-g9qs" labeled
node "gke-kube-ceph-cluster-default-pool-592ab398-qfzk" labeled
node "gke-kube-ceph-cluster-default-pool-592ab398-w226" labeled
node "gke-kube-ceph-cluster-default-pool-592ab398-zt57" labeled
```

Eventually all pods will be running, including a mon and osd for every labeled storage node.

```
→ kubectl get pods -o wide
NAME                        READY     STATUS    RESTARTS   AGE       IP         NODE
ceph-mds-2743106415-n3cp3   1/1       Running   0          2m        10.0.8.4   gke-kube-ceph-cluster-default-pool-592ab398-g9qs
ceph-mon-2416973846-00glw   1/1       Running   0          5m        10.0.3.3   gke-kube-ceph-cluster-default-pool-592ab398-x9nx
ceph-mon-2416973846-5rks2   1/1       Running   0          5m        10.0.1.3   gke-kube-ceph-cluster-default-pool-592ab398-5dhc
ceph-mon-2416973846-vns3q   1/1       Running   0          5m        10.0.2.3   gke-kube-ceph-cluster-default-pool-592ab398-9kqn
ceph-osd-5sp3p              1/1       Running   0          1m        10.0.9.8   gke-kube-ceph-cluster-default-pool-592ab398-5hr0
ceph-osd-6153f              1/1       Running   0          1m        10.0.4.3   gke-kube-ceph-cluster-default-pool-592ab398-qfzk
ceph-osd-6c5nr              1/1       Running   0          1m        10.0.8.3   gke-kube-ceph-cluster-default-pool-592ab398-g9qs
ceph-osd-7kkfl              1/1       Running   0          1m        10.0.0.3   gke-kube-ceph-cluster-default-pool-592ab398-6t50
ceph-osd-qgbp2              1/1       Running   0          1m        10.0.6.3   gke-kube-ceph-cluster-default-pool-592ab398-w226
ceph-osd-rfrk2              1/1       Running   0          1m        10.0.7.4   gke-kube-ceph-cluster-default-pool-592ab398-dthr
ceph-osd-w0b1t              1/1       Running   0          1m        10.0.5.3   gke-kube-ceph-cluster-default-pool-592ab398-zt57
ceph-rgw-384278267-j38r0    1/1       Running   0          2m        10.0.5.4   gke-kube-ceph-cluster-default-pool-592ab398-zt57
ceph-rgw-384278267-vcbrm    1/1       Running   0          2m        10.0.0.4   gke-kube-ceph-cluster-default-pool-592ab398-6t50
ceph-rgw-384278267-zxqs6    1/1       Running   0          2m        10.0.4.4   gke-kube-ceph-cluster-default-pool-592ab398-qfzk
```

And your complete cluster should look something like:

```
→ kubectl get all -o wide
NAME                           READY     STATUS    RESTARTS   AGE       IP         NODE
po/ceph-mds-2743106415-n3cp3   1/1       Running   0          3m        10.0.8.4   gke-kube-ceph-cluster-default-pool-592ab398-g9qs
po/ceph-mon-2416973846-00glw   1/1       Running   0          6m        10.0.3.3   gke-kube-ceph-cluster-default-pool-592ab398-x9nx
po/ceph-mon-2416973846-5rks2   1/1       Running   0          6m        10.0.1.3   gke-kube-ceph-cluster-default-pool-592ab398-5dhc
po/ceph-mon-2416973846-vns3q   1/1       Running   0          6m        10.0.2.3   gke-kube-ceph-cluster-default-pool-592ab398-9kqn
po/ceph-osd-5sp3p              1/1       Running   0          2m        10.0.9.8   gke-kube-ceph-cluster-default-pool-592ab398-5hr0
po/ceph-osd-6153f              1/1       Running   0          2m        10.0.4.3   gke-kube-ceph-cluster-default-pool-592ab398-qfzk
po/ceph-osd-6c5nr              1/1       Running   0          2m        10.0.8.3   gke-kube-ceph-cluster-default-pool-592ab398-g9qs
po/ceph-osd-7kkfl              1/1       Running   0          2m        10.0.0.3   gke-kube-ceph-cluster-default-pool-592ab398-6t50
po/ceph-osd-qgbp2              1/1       Running   0          2m        10.0.6.3   gke-kube-ceph-cluster-default-pool-592ab398-w226
po/ceph-osd-rfrk2              1/1       Running   0          2m        10.0.7.4   gke-kube-ceph-cluster-default-pool-592ab398-dthr
po/ceph-osd-w0b1t              1/1       Running   0          2m        10.0.5.3   gke-kube-ceph-cluster-default-pool-592ab398-zt57
po/ceph-rgw-384278267-j38r0    1/1       Running   0          3m        10.0.5.4   gke-kube-ceph-cluster-default-pool-592ab398-zt57
po/ceph-rgw-384278267-vcbrm    1/1       Running   0          3m        10.0.0.4   gke-kube-ceph-cluster-default-pool-592ab398-6t50
po/ceph-rgw-384278267-zxqs6    1/1       Running   0          3m        10.0.4.4   gke-kube-ceph-cluster-default-pool-592ab398-qfzk

NAME           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE       SELECTOR
svc/ceph-mon   None           <none>           6789/TCP       6m        app=ceph,daemon=mon
svc/ceph-rgw   10.3.240.157   104.198.13.176   80:31499/TCP   3m        app=ceph,daemon=rgw

NAME              DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/ceph-mds   1         1         1            1           3m
deploy/ceph-mon   3         3         3            3           6m
deploy/ceph-rgw   3         3         3            3           3m

NAME                     DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)             SELECTOR
rs/ceph-mds-2743106415   1         1         1         3m        ceph-mds       ceph/daemon:latest   app=ceph,daemon=mds,pod-template-hash=2743106415
rs/ceph-mon-2416973846   3         3         3         6m        ceph-mon       ceph/daemon:latest   app=ceph,daemon=mon,pod-template-hash=2416973846
rs/ceph-rgw-384278267    3         3         3         3m        ceph-rgw       ceph/daemon:latest   app=ceph,daemon=rgw,pod-template-hash=384278267
```

### Check the health status of your Ceph cluster

We'll select a Ceph Mon pod to check the Ceph cluster status.

```
→ export MON_POD_NAME=$(kubectl get pods --selector="app=ceph,daemon=mon" --output=template --template="{{with index .items 0}}{{.metadata.name}}{{end}}")
→ echo ${MON_POD_NAME}
ceph-mon-2416973846-00glw
→ kubectl exec ${MON_POD_NAME} -- ceph -s
    cluster a3985fe9-e376-44aa-a277-d31b70774a81
     health HEALTH_OK
     monmap e2: 3 mons at {ceph-mon-2416973846-00glw=10.0.3.3:6789/0,ceph-mon-2416973846-5rks2=10.0.1.3:6789/0,ceph-mon-2416973846-vns3q=10.0.2.3:6789/0}
            election epoch 6, quorum 0,1,2 ceph-mon-2416973846-5rks2,ceph-mon-2416973846-vns3q,ceph-mon-2416973846-00glw
      fsmap e5: 1/1/1 up {0=mds-ceph-mds-2743106415-n3cp3=up:active}
     osdmap e23: 7 osds: 7 up, 7 in
            flags sortbitwise,require_jewel_osds
      pgmap v132: 464 pgs, 9 pools, 3656 bytes data, 191 objects
            57890 MB used, 603 GB / 659 GB avail
                 464 active+clean
```

### Testing Rados Gateway

Now we'll check if we can access the Ceph cluster's Rados Gateway (RGW) interface externally from the internet. Determine the external IP and verify we can access the RGW interface:

```
→ kubectl get svc -l daemon=rgw
NAME       CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
ceph-rgw   10.3.240.157   104.198.13.176   80:31499/TCP   5m
→ RGW_EXT_IP=$(kubectl get svc -l daemon=rgw | awk '/ceph-rgw/ {print $3}')
→ curl http://${RGW_EXT_IP}
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>
```

Now that we can access it, we'll select a RGW pod to run commands for these examples:

```
→ export RGW_POD_NAME=$(kubectl get pods --selector="app=ceph,daemon=rgw" --output=template --template="{{with index .items 0}}{{.metadata.name}}{{end}}")
→ echo ${RGW_POD_NAME}
ceph-rgw-384278267-j38r0
```

#### S3

##### Preqrequisites

This example will use Python to test the RGW interface using S3. For this, we need the `boto` Python module installed so we use `pip` to install it. See [https://github.com/boto/boto](https://github.com/boto/boto) for other installation methods.

```
sudo pip install boto
```

##### Create a user

Now we execute the command to create a user using the RGW pod name we saved from above.

```
→ kubectl exec ${RGW_POD_NAME} -- radosgw-admin user create --uid=rgwuser --display-name="RGW User" --email=rgwuser@example.com
{
    "user_id": "rgwuser",
    "display_name": "RGW User",
    "email": "rgwuser@example.com",
    "suspended": 0,
    "max_buckets": 1000,
    "auid": 0,
    "subusers": [],
    "keys": [
        {
            "user": "rgwuser",
            "access_key": "U8LFBA1H6RA3SJGCL7YG",
            "secret_key": "5sxEMHOjLIMAogO7AwM9Ab0MSGR6Y3Az1j2LzmPw"
        }
    ],
    "swift_keys": [],
    "caps": [],
    "op_mask": "read, write, delete",
    "default_placement": "",
    "placement_tags": [],
    "bucket_quota": {
        "enabled": false,
        "max_size_kb": -1,
        "max_objects": -1
    },
    "user_quota": {
        "enabled": false,
        "max_size_kb": -1,
        "max_objects": -1
    },
    "temp_url_keys": []
}


```

##### Setup the S3 client test with your IP and keys

Grab the keys that were generated in the above command and use the previously defined `${RGW_EXT_IP}` to set the variables inside the S3 client test:

```
→ S3_ACCESS_KEY=$(kubectl exec ${RGW_POD_NAME} -- radosgw-admin user info --uid=rgwuser | awk '/access_key/ {print $2}' | sed "s/\"/'/g" | sed 's/.$//')
→ echo ${S3_ACCESS_KEY}
'U8LFBA1H6RA3SJGCL7YG'
→ sed -i "s/^access_key = .*/access_key = ${S3_ACCESS_KEY}/" rgw_s3_client.py
→ S3_SECRET_KEY=$(kubectl exec ${RGW_POD_NAME} -- radosgw-admin user info --uid=rgwuser | awk '/secret_key/ {print $2}' | sed "s/\"/'/g")
→ echo ${S3_SECRET_KEY}
'5sxEMHOjLIMAogO7AwM9Ab0MSGR6Y3Az1j2LzmPw'
→ sed -i "s/^secret_key = .*/secret_key = ${S3_SECRET_KEY}/" rgw_s3_client.py
→ sed -i "s/host = .*,/host = '${RGW_EXT_IP}',/" rgw_s3_client.py
```

##### Run the S3 client test

This test will do the following:

1. Create a new test bucket
2. Display the name and creation date of the bucket
3. Add public and private objects with test data in each
4. Prints out the URL for each object

Execute the test and display the results:

```
→ ./rgw_s3_client.py
my-s3-test-bucket       2017-01-07T07:16:25.600Z
http://104.198.13.176/my-s3-test-bucket/hello.txt
http://104.198.13.176/my-s3-test-bucket/secret_plans.txt?Signature=x7dl%2Bng43WNAWMXLlESKIhLa%2BPY%3D&Expires=1483776988&AWSAccessKeyId=U8LFBA1H6RA3SJGCL7YG
→ curl http://104.198.13.176/my-s3-test-bucket/hello.txt
Hello World!
→ curl "http://104.198.13.176/my-s3-test-bucket/secret_plans.txt?Signature=x7dl%2Bng43WNAWMXLlESKIhLa%2BPY%3D&Expires=1483776988&AWSAccessKeyId=U8LFBA1H6RA3SJGCL7YG"
My secret plans!
```

### CephFS and RBD

We must now setup a new Ceph client node that we can install packages on in order to test CephFS and RBD capabilities. This is because the GCI image that Google Container Engine uses is based on Chrome OS and does not have the ability to install packages. See [https://cloud.google.com/container-optimized-os/docs/](https://cloud.google.com/container-optimized-os/docs/) for more details.

#### Setup Ceph client node

We will use the `node-pool` option to add another node to our container cluster pool. To do this, execute the following command:

```
→ gcloud container node-pools create ceph-client --cluster kube-ceph-cluster --image-type=CONTAINER_VM --machine-type n1-standard-2 --num-nodes=1
Creating node pool ceph-client...done.
Created [https://container.googleapis.com/v1/projects/kube-ceph-cluster/zones/us-west1-a/clusters/kube-ceph-cluster/nodePools/ceph-client].
NAME         MACHINE_TYPE   DISK_SIZE_GB  NODE_VERSION
ceph-client  n1-standard-2  100           1.5.1
```

Now you can see that we have 2 pools. The one running our Ceph cluster as part of the `default-pool` and the one we just created for our Ceph client as part of the `ceph-client` pool.

```
→ gcloud container node-pools list --cluster=kube-ceph-cluster
NAME          MACHINE_TYPE   DISK_SIZE_GB  NODE_VERSION
default-pool  n1-standard-2  100           1.5.1
ceph-client   n1-standard-2  100           1.5.1
```

With the node up and ready, we have to label the node's `node-type` as a `ceph-client` type in order for the CephFS and RBD test pods to be eligible to run only on this node. The test pods already specify the `nodeSelector` field of PodSpec when creating the resources. See [http://kubernetes.io/docs/user-guide/node-selection/](http://kubernetes.io/docs/user-guide/node-selection/) for more details.

```
→ CEPH_CLIENT_NODE=$(kubectl get nodes -l cloud.google.com/gke-nodepool=ceph-client | awk '/ceph-client/ {print$1}')
→ echo ${CEPH_CLIENT_NODE}
gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
→ kubectl label node ${CEPH_CLIENT_NODE} node-type=ceph-client
node "gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7" labeled
```

#### Install Ceph and RBD utilities on the client node

The Kubernetes kubelet shells out to system utilities to mount Ceph volumes. This means that every node that will run pods requiring the mounting of Ceph volumes must have these utilities installed.

We selected the `--image-type=CONTAINER_VM` when we created the Ceph client node and this particular VM image is a Debian 7 (wheezy) image as of the time of this writing. So for Debian-based distros we install the following:

```
apt-get install ceph-fs-common ceph-common
```

This can be achieved programatically by using the already created `CEPH_CLIENT_NODE` variable from above and issuing:

```
→ gcloud compute ssh ${CEPH_CLIENT_NODE} --command "sudo apt-get install -y ceph-fs-common ceph-common"
Warning: Permanently added 'compute.1623103430872343632' (ECDSA) to the list of known hosts.
Reading package lists...
Building dependency tree...
Reading state information...
The following extra packages will be installed:
  javascript-common libboost-thread1.49.0 libcephfs1 libgoogle-perftools4
  libjs-jquery libnspr4 libnss3 librados2 librbd1 libtcmalloc-minimal4
  libunwind7 python-ceph python-chardet python-flask python-gevent
  python-greenlet python-oauthlib python-openssl python-requests python-six
  python-werkzeug wwwconfig-common
Suggested packages:
  ceph ceph-mds apache2 httpd python-gevent-doc python-gevent-dbg
  python-greenlet-doc python-greenlet-dev python-greenlet-dbg
  python-openssl-doc python-openssl-dbg ipython python-genshi python-lxml
  python-memcache libjs-sphinxdoc mysql-client postgresql-client
The following NEW packages will be installed:
  ceph-common ceph-fs-common javascript-common libboost-thread1.49.0
  libcephfs1 libgoogle-perftools4 libjs-jquery libnspr4 libnss3 librados2
  librbd1 libtcmalloc-minimal4 libunwind7 python-ceph python-chardet
  python-flask python-gevent python-greenlet python-oauthlib python-openssl
  python-requests python-six python-werkzeug wwwconfig-common
0 upgraded, 24 newly installed, 0 to remove and 6 not upgraded.
Need to get 16.5 MB of archives.
After this operation, 56.1 MB of additional disk space will be used.
...
...
...
```

#### Mounting CephFS in a pod

First we must add the admin client key to our current `ceph` namespace. However, this admin client key has already been added by the `create_secrets.sh` script that generated and created the secrets so we can skip this step now.

Next, because Kubernetes installs do not configure the nodes’ `resolv.conf` files to use the cluster DNS by default, we cannot rely on using the Ceph Monitor DNS names in the following tests. This is a known issue and you can get more details in the **Known Issues** section at [http://kubernetes.io/docs/admin/dns/](http://kubernetes.io/docs/admin/dns/).

Instead, we'll have to manually update the test resouces with the Ceph Monitor IP addresses. To get a ceph-mon pod IP address we can issue:

```
→ MON_POD_IP=$(kubectl get pods --selector="app=ceph,daemon=mon" --output=template --template="{{with index .items 0}}{{.status.podIP}}{{end}}")
→ echo ${MON_POD_IP}
10.0.3.3
```
We then modify `ceph-cephfs-test.yaml` to use this ceph-mon pod IP address:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" ceph-cephfs-test.yaml
```

Also modify the `node-type` to use `ceph-client`:

```
sed -i 's/node-type: storage/node-type: ceph-client/' ceph-cephfs-test.yaml
```

We're now ready to create the cephfs test:

```
→ kubectl create -f ceph-cephfs-test.yaml
pod "ceph-cephfs-test" created
```

Verify the pod is up and running:

```
→ kubectl get pod -l test=cephfs -o wide --watch
NAME               READY     STATUS    RESTARTS   AGE       IP          NODE
ceph-cephfs-test   1/1       Running   0          7s        10.0.10.3   gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
```

Once the pod is up and running you should be able to see the filesystem mounted as a `ceph` filesystem type:

```
→ kubectl exec -it --namespace=ceph ceph-cephfs-test -- df -hT
Filesystem           Type            Size      Used Available Use% Mounted on
none                 aufs           98.3G      3.4G     90.8G   4% /
tmpfs                tmpfs           3.7G         0      3.7G   0% /dev
tmpfs                tmpfs           3.7G         0      3.7G   0% /sys/fs/cgroup
10.0.3.3:6789:/      ceph          659.7G     56.7G    603.0G   9% /mnt/cephfs
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /dev/termination-log
tmpfs                tmpfs           3.7G     12.0K      3.7G   0% /var/run/secrets/kubernetes.io/serviceaccount
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/resolv.conf
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/hostname
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/hosts
shm                  tmpfs          64.0M         0     64.0M   0% /dev/shm
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/kcore
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/timer_stats
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/sched_debug
```

##### Testing CephFS mount

A simple test we can perform is to write a test file and then read it back:

```
→ kubectl exec -it ceph-cephfs-test -- sh -c "echo Hello CephFS World! > /mnt/cephfs/testfile.txt"
→ kubectl exec -it ceph-cephfs-test -- cat /mnt/cephfs/testfile.txt
Hello CephFS World!
```

#### Mounting Ceph RBD in a pod

First we have to create an RBD volume. We already have a Ceph Monitor pod name assigned to the `MON_POD_NAME` variable from previously so we'll re-use it:

```
→ kubectl exec -it ${MON_POD_NAME} -- rbd create ceph-rbd-test --size 20G
→ kubectl exec -it ${MON_POD_NAME} -- rbd info ceph-rbd-test
rbd image 'ceph-rbd-test':
        size 20480 MB in 5120 objects
        order 22 (4096 kB objects)
        block_name_prefix: rbd_data.10422ae8944a
        format: 2
        features: layering
        flags:
```

The same caveats apply for RBDs as Ceph FS volumes so we edit the pod IP accordingly:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" ceph-rbd-test.yaml
```

Then modify the `node-type` to use `ceph-client`:

```
sed -i 's/node-type: storage/node-type: ceph-client/' ceph-rbd-test.yaml
```

Once you're set just create the resource and check its status:

```
→ kubectl create -f ceph-rbd-test.yaml
pod "ceph-rbd-test" created
→ kubectl get pods -l test=rbd -o wide --watch
NAME            READY     STATUS              RESTARTS   AGE       IP        NODE
ceph-rbd-test   0/1       ContainerCreating   0          5s        <none>    gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
NAME            READY     STATUS    RESTARTS   AGE       IP          NODE
ceph-rbd-test   1/1       Running   0          9s        10.0.10.4   gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
```

Again you should see your `ext4` RBD mount, but with 20 GBs free:

```
→ kubectl exec ceph-rbd-test -- df -hT
Filesystem           Type            Size      Used Available Use% Mounted on
none                 aufs           98.3G      3.4G     90.8G   4% /
tmpfs                tmpfs           3.7G         0      3.7G   0% /dev
tmpfs                tmpfs           3.7G         0      3.7G   0% /sys/fs/cgroup
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /dev/termination-log
/dev/rbd0            ext4           19.6G     43.9M     18.5G   0% /mnt/cephrbd
tmpfs                tmpfs           3.7G     12.0K      3.7G   0% /var/run/secrets/kubernetes.io/serviceaccount
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/resolv.conf
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/hostname
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/hosts
shm                  tmpfs          64.0M         0     64.0M   0% /dev/shm
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/kcore
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/timer_stats
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/sched_debug
```

##### Testing RBD mount

We can do the same simple test to write a test file and then read it back:

```
→ kubectl exec -it ceph-rbd-test -- sh -c "echo Hello Ceph RBD World! > /mnt/cephrbd/testfile.txt"
→ kubectl exec -it ceph-rbd-test -- cat /mnt/cephrbd/testfile.txt
Hello Ceph RBD World!
```

### Persistent Volume Claim with Static Provisioning

#### Rados Block Device (RBD)

For persistent volume claims with static provisioning we need to add the Ceph admin keyring as a Kubernetes secret so that our persistent volume resource will have the necessary permissions to create the persistent volume. The name given to the Ceph admin keyring secret must match the name given to the secret in the persistent volume resource we create later. For now let's create the secret and use the same `${MON_POD_NAME}` we set previously:

```
→ ADMIN_KEYRING=$(kubectl exec ${MON_POD_NAME} -- ceph auth get client.admin 2>&1 | awk '/key =/ {print$3}')
→ kubectl create secret generic ceph-admin-secret --from-literal=key="${ADMIN_KEYRING}"
secret "ceph-admin-secret" created
→ kubectl get secret ceph-admin-secret
NAME                TYPE      DATA      AGE
ceph-admin-secret   Opaque    1         13s
```

Now we create the RBD image for the persistent volume:

```
→ kubectl exec ${MON_POD_NAME} -- rbd create ceph-rbd-pv-test --size 10G
→ kubectl exec ${MON_POD_NAME} -- rbd info ceph-rbd-pv-test
rbd image 'ceph-rbd-pv-test':
        size 10240 MB in 2560 objects
        order 22 (4096 kB objects)
        block_name_prefix: rbd_data.1049238e1f29
        format: 2
        features: layering
        flags:
```

We're almost ready to create the persistent volume resource but we need to modify the Ceph MON DNS to use the IP address. As previously mentioned, this is because Kubernetes installs do not configure the nodes’ `resolv.conf` files to use the cluster DNS by default, so we cannot rely on using the Ceph Monitor DNS names. This is a known issue and you can get more details in the **Known Issues** section at [http://kubernetes.io/docs/admin/dns/](http://kubernetes.io/docs/admin/dns/).

Using the same `${MON_POD_IP}` we set earlier issue the command:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" rbd-pv.yaml
```

Create the persistent volume and check its status:

```
→ kubectl create -f rbd-pv.yaml
persistentvolume "ceph-pv" created
→ kubectl get pv
NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
ceph-pv   10Gi       RWO           Recycle         Available                       4s
→ kubectl describe pv
Name:           ceph-pv
Labels:         <none>
StorageClass:
Status:         Available
Claim:
Reclaim Policy: Recycle
Access Modes:   RWO
Capacity:       10Gi
Message:
Source:
    Type:               RBD (a Rados Block Device mount on the host that shares a pod's lifetime)
    CephMonitors:       [10.0.3.3:6789]
    RBDImage:           ceph-rbd-pv-test
    FSType:             ext4
    RBDPool:            rbd
    RadosUser:          admin
    Keyring:            /etc/ceph/keyring
    SecretRef:          &{ceph-admin-secret}
    ReadOnly:           false
No events.
```

Next we create the persistent volume claim:

```
→ kubectl create -f rbd-pv-claim.yaml
persistentvolumeclaim "ceph-pv-claim" created
→ kubectl get pvc
NAME            STATUS    VOLUME    CAPACITY   ACCESSMODES   AGE
ceph-pv-claim   Bound     ceph-pv   10Gi       RWO           7s
→ kubectl describe pvc
Name:           ceph-pv-claim
Namespace:      ceph
StorageClass:
Status:         Bound
Volume:         ceph-pv
Labels:         <none>
Capacity:       10Gi
Access Modes:   RWO
No events.
```

Lastly, we create a test pod to utilize the persistent volume claim. This test pod still uses the `node-type: ceph-client` `nodeSelector` so that we target the `ceph-client` node i.e. the one we were able to install the necessary Ceph and RBD utilities on.

```
→ kubectl create -f rbd-pvc-pod.yaml
pod "ceph-rbd-pv-pod1" created
→ kubectl get pod -l test=rbd-pvc-pod -o wide --watch
NAME           READY     STATUS              RESTARTS   AGE       IP        NODE
ceph-rbd-pv-pod1   0/1       ContainerCreating   0          5s        <none>    gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
NAME           READY     STATUS    RESTARTS   AGE       IP          NODE
ceph-rbd-pv-pod1   1/1       Running   0          6s        10.0.10.5   gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
```

Once the pod is running we can display the RBD PVC mount with 10G free:

```
→ kubectl exec ceph-rbd-pv-pod1 -- df -hT
Filesystem           Type            Size      Used Available Use% Mounted on
none                 aufs           98.3G      3.4G     90.8G   4% /
tmpfs                tmpfs           3.7G         0      3.7G   0% /dev
tmpfs                tmpfs           3.7G         0      3.7G   0% /sys/fs/cgroup
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /dev/termination-log
/dev/rbd1            ext4            9.7G     22.5M      9.2G   0% /mnt/ceph-rbd-pvc
tmpfs                tmpfs           3.7G     12.0K      3.7G   0% /var/run/secrets/kubernetes.io/serviceaccount
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/resolv.conf
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/hostname
/dev/sda1            ext4           98.3G      3.4G     90.8G   4% /etc/hosts
shm                  tmpfs          64.0M         0     64.0M   0% /dev/shm
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/kcore
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/timer_stats
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/sched_debug
```

Make sure we can do a simple test to write a test file and then read it back:

```
→ kubectl exec ceph-rbd-pv-pod1 -- sh -c "echo Hello RBD PVC World! > /mnt/ceph-rbd-pvc/testfile.txt"
→ kubectl exec ceph-rbd-pv-pod1 -- cat /mnt/ceph-rbd-pvc/testfile.txt
Hello RBD PVC World!
```

And that shows we've set up an RBD persistent volume claim with static provisioning that can be consumed by a pod!

#### Ceph Filesystem (CephFS)

We will be using the same MON_POD_IP and ceph-admin-secret that were created above so make sure these are set before continuing.

Using the same `${MON_POD_IP}` we set earlier issue the command:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" cephfs-pv.yaml
```

Create the persistent volume and check its status:

```
→ kubectl create -f cephfs-pv.yaml
persistentvolume "cephfs-pv" created
→ kubectl get pv
NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM                REASON    AGE
ceph-pv   10Gi       RWO           Recycle         Bound       ceph/ceph-pv-claim             4m
cephfs-pv 10Gi       RWX           Recycle         Available                                  8s
```

Next we create the persistent volume claim:

```
→ kubectl create -f cephfs-pv-claim.yaml
persistentvolumeclaim "cephfs-pv-claim" created
→ kubectl get pvc
NAME              STATUS    VOLUME      CAPACITY   ACCESSMODES   AGE
ceph-pv-claim     Bound     ceph-pv     10Gi       RWO           4m
cephfs-pv-claim   Bound     cephfs-pv   10Gi       RWX           9s
```

Lastly, we create a test pod to utilize the persistent volume claim. This test pod still uses the `node-type: ceph-client` `nodeSelector` so that we target the `ceph-client` node i.e. the one we were able to install the necessary CephFS utilities on.

```
→ kubectl create -f cephfs-pvc-pod.yaml
pod "cephfs-pv-pod1" created
→ kubectl get pod -l test=cephfs-pvc-pod -o wide --watch
NAME             READY     STATUS              RESTARTS   AGE       IP        NODE
cephfs-pv-pod1   0/1       ContainerCreating   0          5s        <none>    gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
NAME             READY     STATUS    RESTARTS   AGE       IP          NODE
cephfs-pv-pod1   1/1       Running   0          6s        10.0.10.7   gke-kube-ceph-cluster-ceph-client-57758f2d-nkv7
```
Once the pod is running we can display the CephFS PVC mount:

```
→ kubectl exec -it cephfs-pv-pod1 -- df -hT
Filesystem           Type            Size      Used Available Use% Mounted on
none                 aufs           98.3G      3.6G     90.5G   4% /
tmpfs                tmpfs           3.7G         0      3.7G   0% /dev
tmpfs                tmpfs           3.7G         0      3.7G   0% /sys/fs/cgroup
/dev/sda1            ext4           98.3G      3.6G     90.5G   4% /dev/termination-log
10.0.3.3:6789:/      ceph          659.7G     58.9G    600.8G   9% /mnt/cephfs-pvc
tmpfs                tmpfs           3.7G     12.0K      3.7G   0% /var/run/secrets/kubernetes.io/serviceaccount
/dev/sda1            ext4           98.3G      3.6G     90.5G   4% /etc/resolv.conf
/dev/sda1            ext4           98.3G      3.6G     90.5G   4% /etc/hostname
/dev/sda1            ext4           98.3G      3.6G     90.5G   4% /etc/hosts
shm                  tmpfs          64.0M         0     64.0M   0% /dev/shm
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/kcore
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/timer_stats
tmpfs                tmpfs           3.7G         0      3.7G   0% /proc/sched_debug
```

Make sure we can do a simple test to write a test file and then read it back:

```
→ kubectl exec -it cephfs-pv-pod1 -- sh -c "echo Hello cephfs PVC World! > /mnt/cephfs-pvc/testfile.txt"
→ kubectl exec -it cephfs-pv-pod1 -- cat /mnt/cephfs-pvc/testfile.txt
Hello cephfs PVC World!
```

And that shows we've set up an CephFS persistent volume claim with static provisioning that can be consumed by a pod!

### Persistent Volume Claim with Dynamic Provisioning (TBD)

#### Preqrequisites
- Kubernetes version 1.5.1
- Ceph and RBD utilities installed on:
    - Ceph Monitor nodes
    - Ceph client node(s)
