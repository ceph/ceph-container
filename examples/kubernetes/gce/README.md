# Ceph on GCE Kubernetes cluster

This Guide will take you through the process of deploying a Ceph cluster on to a GCE Kubernetes cluster.

## Client Requirements

In addition to `kubectl`, `jinja2` or `sigil` is required for template handling and must be installed in your system PATH. Instructions can be found here
for `jinja2` <https://github.com/mattrobenolt/jinja2-cli> (install the optional yaml support as well) or here for `sigil` <https://github.com/gliderlabs/sigil>.

## Cluster Requirements

At a High level:

- Google Cloud Platform account with a project created to work under.
- At least 23 virtual CPUs available in your zone. If you do not have at least 23 virtual CPUs, you'll have to decrease the number of pods, CPU requests/limit amounts for deployment specs, and/or adjust the default placement group numbers so that we have the right amount of placement groups per OSD (300) ratio. Adjusting the default placement group number is likely the easiest option for you. Otherwise increase your default 24 virtual CPU quota provided by Google in order to increase the number of worker nodes.
- Ceph and RBD utilities must be installed on any host/container that `kube-controller-manager` or `kubelet` is running on that will be hosting Ceph client pods (more later).

## Set up a Kubernetes container cluster on GCE

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
If it doesn't match this, then make sure you make the appropriate changes i.e. `region` and `zone` in the `gcloud compute create` and `gcloud compute delete` commands provided by the automated deployment. Otherwise, run `gcloud init` or the commands below to set it up correctly:

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

### Create Kubernetes cluster on GCE

Now we need to set up a GCE Kubernetes cluster. We will start with 13 nodes: 3 controller nodes (for HA demonstration purposes) and 10 worker nodes. The worker nodes will consist of 3 ceph-mon nodes and 7 storage nodes to run the Ceph storage cluster i.e. OSDs, MDSs, RGWs, and CephFS/RBD clients.

In order to create a Kubernetes cluster, we will be making use of [https://github.com/kelseyhightower/kubernetes-the-hard-way](https://github.com/kelseyhightower/kubernetes-the-hard-way). You can either run through the steps manually or use some automated scripts that do it for you. There is currently a PR open to include the scripts in that repo, but in the meantime you can get them from [https://github.com/font/kubernetes-the-hard-way/tree/scripts](https://github.com/font/kubernetes-the-hard-way/tree/scripts).

In your workspace clone the repo and change into the directory:

```
git clone git@github.com:font/kubernetes-the-hard-way.git
cd kubernetes-the-hard-way
git checkout scripts
cd scripts
```

We'll need to set 3 environment variables to get started. You can use combinations of workers and controllers with different Kubernetes versions, but the below settings have been tested to work. Other variations of workers and newer versions of Kubernetes should also work, but only 3 controllers have been tested thus far.

```
export NUM_CONTROLLERS=3
export NUM_WORKERS=10
export KUBERNETES_VERSION=v1.5.1
```

Let's start by creating our Kubernetes cluster using the below command. This will pipe all the detailed output to a log file and throw the command in the background so you can start tailing the log. Remember that the scripts do not currently install `kubectl` so you should already have that installed on your remote client or install it now before proceeding.

```
./kube-up.sh &> kube-up.log &
tail -f kube-up.log
```

After the script completes you should have a working Kubernetes cluster and remote access to it using `kubectl`. If you would like to perform a quick smoke test you can execute the script `smoke-test.sh` and you should see the html output of the root of the nginx web server. Once you're done with it you can execute `cleanup-smoke-test.sh` to clean it up.

Verify the Kubernetes cluster is up and you have remote access to it:

```
→ gcloud compute instances list
NAME         ZONE        MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP      STATUS
controller0  us-west1-a  n1-standard-1               10.240.0.10  104.196.230.65   RUNNING
controller1  us-west1-a  n1-standard-1               10.240.0.11  104.198.108.19   RUNNING
controller2  us-west1-a  n1-standard-1               10.240.0.12  104.199.119.12   RUNNING
worker0      us-west1-a  n1-standard-2               10.240.0.20  104.196.229.155  RUNNING
worker1      us-west1-a  n1-standard-2               10.240.0.21  104.196.252.130  RUNNING
worker2      us-west1-a  n1-standard-2               10.240.0.22  104.196.249.1    RUNNING
worker3      us-west1-a  n1-standard-2               10.240.0.23  104.196.253.248  RUNNING
worker4      us-west1-a  n1-standard-2               10.240.0.24  104.196.242.25   RUNNING
worker5      us-west1-a  n1-standard-2               10.240.0.25  104.196.249.85   RUNNING
worker6      us-west1-a  n1-standard-2               10.240.0.26  104.196.245.245  RUNNING
worker7      us-west1-a  n1-standard-2               10.240.0.27  104.198.14.100   RUNNING
worker8      us-west1-a  n1-standard-2               10.240.0.28  104.196.224.87   RUNNING
worker9      us-west1-a  n1-standard-2               10.240.0.29  104.198.7.157    RUNNING
→ kubectl get nodes
NAME      STATUS    AGE
worker0   Ready     39m
worker1   Ready     38m
worker2   Ready     37m
worker3   Ready     36m
worker4   Ready     35m
worker5   Ready     34m
worker6   Ready     33m
worker7   Ready     32m
worker8   Ready     31m
worker9   Ready     30m
```

If you do not see output similar to the above or if any issues came up along the way you can reference the log file for details.

### Create a clone of this repository in your work space

```
git clone https://github.com/ceph/ceph-container.git
cd ceph-container/examples/kubernetes
```

### Override default settings

These will be picked up by `jinja2` or `sigil` when generating the Kubernetes secrets in the next section.

#### Override the default network settings

By default, `10.244.0.0/16` is used for the `cluster_network` and `public_network` in the generated ceph.conf. To change these defaults, set the following environment variables according to your cluster CIDR network requirements. These IPs should be set according to the range of your Pod IPs in your Kubernetes cluster as set by the `--cluster-cidr=10.200.0.0/16` option to `kube-controller-manager` on your controller nodes:

##### for jinja2

using your text editor of choice open: generator/templates/ceph/ceph.conf.jinja

under the [osd] heading, change the cluster_network and public_network:
```
cluster_network = {{ osd_cluster_network|default('10.200.0.0/16') }}
public_network = {{ osd_public_network|default('10.200.0.0/16') }}
```

##### for sigil

```
→ CLUSTER_NETWORK=10.200.0.0/16
→ export osd_cluster_network=${CLUSTER_NETWORK}
→ export osd_public_network=${CLUSTER_NETWORK}
→ printenv | grep network
osd_cluster_network=10.200.0.0/16
osd_public_network=10.200.0.0/16
```

#### Override the default number of placement groups

By default, 128 is used for the `osd_pool_default_pg_num` and `osd_pool_default_pgp_num` in the generated ceph.conf. That's because the recommended number of placement groups per pool for less than 5 OSDs is 128. This means that we would need to increase the number of OSDs to maintain a healthy placement group to OSD ratio (300) when using a default pool replication size of 3 set by `osd_pool_default_size`. However, we have a default limit of 24 virtual CPUs provided by the Google Cloud Platform without requesting an increase in CPU quota. Therefore, we will have to reduce the default number of placement groups in order to achieve a Ceph cluster `HEALTH_OK` status using the same number of OSDs to stay within our CPU quota limit. This is okay for demonstration purposes but is not recommended for production. See [http://docs.ceph.com/docs/main/rados/operations/placement-groups/](http://docs.ceph.com/docs/main/rados/operations/placement-groups/) for more information.

Let's go ahead and reduce the default number of placement groups from 128 down to 32:

##### for jinja2

using your text editor of choice open: generator/templates/ceph/ceph.conf.jinja

under the #auth heading, change the osd_pool_default_pg_num and osd_pool_default_pgp_num:
```
osd_pool_default_pg_num = {{ global_osd_pool_default_pg_num|default("32") }}
osd_pool_default_pgp_num = {{ global_osd_pool_default_pgp_num|default("32") }}
```

##### for sigil

```
export global_osd_pool_default_pg_num=32
export global_osd_pool_default_pgp_num=32
```

### Generate Ceph Kubernetes keys and configuration

Run the following command to generate the required configuration and keys. This will create a Kubernetes `ceph` namespace, then create secrets in that namespace using the generated configuration and keys.

```
./create_secrets.sh
```

Please note that you should save the output files of this command. Future invocations of scripts will overwrite existing keys and configuration. If you lose these files they can still be retrieved from Kubernetes via `kubectl get secret`.

### Configure kubectl to use the ceph namespace in current default-context

After setting the current context's namespace, all subsequent comands will default to the `ceph` namespace. So let's do that now:

```
→ kubectl config set-context default-context --namespace ceph
Context "default-context" set.
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
ceph-mon-2416973846-2jxls   0/1       ContainerCreating   0          2s        <none>    worker2
ceph-mon-2416973846-hsmp5   0/1       ContainerCreating   0          2s        <none>    worker5
ceph-mon-2416973846-phx6z   0/1       ContainerCreating   0          2s        <none>    worker6
NAME                        READY     STATUS    RESTARTS   AGE       IP           NODE
ceph-mon-2416973846-hsmp5   0/1       Running   0          41s       10.200.5.3   worker5
ceph-mon-2416973846-phx6z   0/1       Running   0         44s       10.200.6.5   worker6
ceph-mon-2416973846-2jxls   0/1       Running   0         48s       10.200.2.4   worker2
ceph-mon-2416973846-phx6z   1/1       Running   0         50s       10.200.6.5   worker6
ceph-mon-2416973846-2jxls   1/1       Running   0         50s       10.200.2.4   worker2
ceph-mon-2416973846-hsmp5   1/1       Running   0         50s       10.200.5.3   worker5
```

Your cluster should now look something like this:

```
→ kubectl get all -o wide
NAME                           READY     STATUS    RESTARTS   AGE       IP           NODE
po/ceph-mon-2416973846-2jxls   1/1       Running   0          1m        10.200.2.4   worker2
po/ceph-mon-2416973846-hsmp5   1/1       Running   0          1m        10.200.5.3   worker5
po/ceph-mon-2416973846-phx6z   1/1       Running   0          1m        10.200.6.5   worker6

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

In order to deploy the RGW component we must adjust the RGW service to instead use `--type=NodePort`. Using `--type=LoadBalancer` will not work because we did not configure a cloud provider when bootstrapping this cluster. So let's adjust this first:

```
sed -i 's/type: .*/type: NodePort/' ceph-rgw-v1-svc.yaml
```

Now we're ready to deploy the service and deployment:

```
→ kubectl create -f ceph-rgw-v1-svc.yaml -f ceph-rgw-v1-dp.yaml
service "ceph-rgw" created
deployment "ceph-rgw" created
```

### Label your storage nodes

You must label your storage nodes in order to run other Ceph daemon pods on them. You can label as many nodes as you want OSDs, MDSs, and RGWs to run on as long as there are enough resources on that node. If you want all nodes - including the ones running Ceph monitor pods - in your Kubernetes cluster to be eligible to run Ceph OSDs, MDSs, and RGWs, label them all.

```
kubectl label nodes node-type=storage --all
```
For this particular example, we'll just choose the remaining 7 nodes that are not currently running Ceph Monitor pods.

```
→ kubectl get pods -o wide
NAME                        READY     STATUS    RESTARTS   AGE       IP           NODE
ceph-mds-2743106415-l5189   0/1       Pending   0          2m        <none>
ceph-mon-2416973846-2jxls   1/1       Running   0          4m        10.200.2.4   worker2
ceph-mon-2416973846-hsmp5   1/1       Running   0          4m        10.200.5.3   worker5
ceph-mon-2416973846-phx6z   1/1       Running   0          4m        10.200.6.5   worker6
ceph-rgw-384278267-crnv8    0/1       Pending   0          1m        <none>
ceph-rgw-384278267-kjlbs    0/1       Pending   0          1m        <none>
ceph-rgw-384278267-s13fn    0/1       Pending   0          1m        <none>
→ kubectl get nodes
NAME      STATUS    AGE
worker0   Ready     2h
worker1   Ready     2h
worker2   Ready     2h
worker3   Ready     2h
worker4   Ready     2h
worker5   Ready     2h
worker6   Ready     2h
worker7   Ready     2h
worker8   Ready     2h
worker9   Ready     2h
→ MON_NODES=$(kubectl get pods -o wide | awk '/ceph-mon/ {print $7}')
→ echo ${MON_NODES}
worker2 worker5 worker6
→ UNUSED_NODES=$(kubectl get nodes | grep -v "${MON_NODES}" | awk '/Ready/ {print $1}')
→ echo ${UNUSED_NODES}
worker0 worker1 worker3 worker4 worker7 worker8 worker9
→ for i in ${UNUSED_NODES}; do kubectl label node ${i} node-type=storage; done
node "worker0" labeled
node "worker1" labeled
node "worker3" labeled
node "worker4" labeled
node "worker7" labeled
node "worker8" labeled
node "worker9" labeled
```

Eventually all pods will be running, including a mon and osd for every labeled storage node.

```
→ kubectl get pods -o wide
NAME                        READY     STATUS    RESTARTS   AGE       IP           NODE
ceph-mds-2743106415-l5189   1/1       Running   0          4m        10.200.0.4   worker0
ceph-mon-2416973846-2jxls   1/1       Running   0          6m        10.200.2.4   worker2
ceph-mon-2416973846-hsmp5   1/1       Running   0          6m        10.200.5.3   worker5
ceph-mon-2416973846-phx6z   1/1       Running   0          6m        10.200.6.5   worker6
ceph-osd-4v91x              1/1       Running   0          1m        10.200.4.4   worker4
ceph-osd-4z2bw              1/1       Running   0          1m        10.200.9.3   worker9
ceph-osd-8fq41              1/1       Running   0          1m        10.200.7.3   worker7
ceph-osd-chjm1              1/1       Running   0          1m        10.200.3.3   worker3
ceph-osd-fcqfp              1/1       Running   0          1m        10.200.8.3   worker8
ceph-osd-jf6rv              1/1       Running   0          1m        10.200.0.3   worker0
ceph-osd-mcwsw              1/1       Running   0          1m        10.200.1.6   worker1
ceph-rgw-384278267-crnv8    1/1       Running   0          3m        10.200.1.7   worker1
ceph-rgw-384278267-kjlbs    1/1       Running   0          3m        10.200.8.4   worker8
ceph-rgw-384278267-s13fn    1/1       Running   0          3m        10.200.3.4   worker3
```

And your complete cluster should look something like:

```
→ kubectl get all -o wide
NAME                           READY     STATUS    RESTARTS   AGE       IP           NODE
po/ceph-mds-2743106415-l5189   1/1       Running   0          4m        10.200.0.4   worker0
po/ceph-mon-2416973846-2jxls   1/1       Running   0          7m        10.200.2.4   worker2
po/ceph-mon-2416973846-hsmp5   1/1       Running   0          7m        10.200.5.3   worker5
po/ceph-mon-2416973846-phx6z   1/1       Running   0          7m        10.200.6.5   worker6
po/ceph-osd-4v91x              1/1       Running   0          2m        10.200.4.4   worker4
po/ceph-osd-4z2bw              1/1       Running   0          1m        10.200.9.3   worker9
po/ceph-osd-8fq41              1/1       Running   0          2m        10.200.7.3   worker7
po/ceph-osd-chjm1              1/1       Running   0          2m        10.200.3.3   worker3
po/ceph-osd-fcqfp              1/1       Running   0          1m        10.200.8.3   worker8
po/ceph-osd-jf6rv              1/1       Running   0          2m        10.200.0.3   worker0
po/ceph-osd-mcwsw              1/1       Running   0          2m        10.200.1.6   worker1
po/ceph-rgw-384278267-crnv8    1/1       Running   0          4m        10.200.1.7   worker1
po/ceph-rgw-384278267-kjlbs    1/1       Running   0          4m        10.200.8.4   worker8
po/ceph-rgw-384278267-s13fn    1/1       Running   0          4m        10.200.3.4   worker3

NAME           CLUSTER-IP   EXTERNAL-IP   PORT(S)        AGE       SELECTOR
svc/ceph-mon   None         <none>        6789/TCP       7m        app=ceph,daemon=mon
svc/ceph-rgw   10.32.0.41   <nodes>       80:31977/TCP   4m        app=ceph,daemon=rgw

NAME              DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/ceph-mds   1         1         1            1           4m
deploy/ceph-mon   3         3         3            3           7m
deploy/ceph-rgw   3         3         3            3           4m

NAME                     DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)             SELECTOR
rs/ceph-mds-2743106415   1         1         1         4m        ceph-mds       ceph/daemon:latest   app=ceph,daemon=mds,pod-template-hash=2743106415
rs/ceph-mon-2416973846   3         3         3         7m        ceph-mon       ceph/daemon:latest   app=ceph,daemon=mon,pod-template-hash=2416973846
rs/ceph-rgw-384278267    3         3         3         4m        ceph-rgw       ceph/daemon:latest   app=ceph,daemon=rgw,pod-template-hash=384278267
```

### Check the health status of your Ceph cluster

We'll select a Ceph Mon pod to check the Ceph cluster status.

```
→ export MON_POD_NAME=$(kubectl get pods --selector="app=ceph,daemon=mon" --output=template --template="{{with index .items 0}}{{.metadata.name}}{{end}}")
→ echo ${MON_POD_NAME}
ceph-mon-2416973846-2jxls
→ kubectl exec ${MON_POD_NAME} -- ceph -s
    cluster b7793e09-ec21-40c4-a659-32bcf2ef003c
     health HEALTH_OK
     monmap e3: 3 mons at {ceph-mon-2416973846-2jxls=10.200.2.4:6789/0,ceph-mon-2416973846-hsmp5=10.200.5.3:6789/0,ceph-mon-2416973846-phx6z=10.200.6.5:6789/0}
            election epoch 6, quorum 0,1,2 ceph-mon-2416973846-2jxls,ceph-mon-2416973846-hsmp5,ceph-mon-2416973846-phx6z
      fsmap e5: 1/1/1 up {0=mds-ceph-mds-2743106415-l5189=up:active}
     osdmap e21: 7 osds: 7 up, 7 in
            flags sortbitwise,require_jewel_osds
      pgmap v56: 272 pgs, 9 pools, 3656 bytes data, 191 objects
            54862 MB used, 1303 GB / 1356 GB avail
                 272 active+clean
```

### Testing Rados Gateway

Now we'll check if we can access the Ceph cluster's Rados Gateway (RGW) interface externally from the internet. First we grab the NodePort that was setup for the RGW service:

```
→ RGW_NODE_PORT=$(kubectl get svc ceph-rgw --output=jsonpath='{range .spec.ports[0]}{.nodePort}')
→ echo ${RGW_NODE_PORT}
31977
```
Next create the node port firewall rule:

```
→ gcloud compute firewall-rules create kubernetes-rgw-service --allow=tcp:${RGW_NODE_PORT} --network kubernetes
Created [https://www.googleapis.com/compute/v1/projects/kube-ceph-cluster/global/firewalls/kubernetes-rgw-service].
NAME                    NETWORK     SRC_RANGES  RULES      SRC_TAGS  TARGET_TAGS
kubernetes-rgw-service  kubernetes  0.0.0.0/0   tcp:31977
```

Grab the external IP of one of the worker nodes:

```
NODE_PUBLIC_IP=$(gcloud compute instances describe worker0 --format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
```

Test the RGW service using curl:

```
→ curl http://${NODE_PUBLIC_IP}:${RGW_NODE_PORT}
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>
```

Now that we can access the RGW interface, we'll select an RGW pod to run commands for the following examples:

```
→ export RGW_POD_NAME=$(kubectl get pods --selector="app=ceph,daemon=rgw" --output=template --template="{{with index .items 0}}{{.metadata.name}}{{end}}")
→ echo ${RGW_POD_NAME}
ceph-rgw-384278267-crnv8
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
            "access_key": "C18XSK449ZTBJJ2BPGF7",
            "secret_key": "kxGX71IR0KmFLnoph1gFrmVCzUbzRqrNtzOeLVgA"
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

Grab the keys that were generated in the above command and use the previously defined `NODE_PUBLIC_IP` and `RGW_NODE_PORT` to set the variables inside the S3 client test:

```
→ S3_ACCESS_KEY=$(kubectl exec ${RGW_POD_NAME} -- radosgw-admin user info --uid=rgwuser | awk '/access_key/ {print $2}' | sed "s/\"/'/g" | sed 's/.$//')
→ echo ${S3_ACCESS_KEY}
'C18XSK449ZTBJJ2BPGF7'
→ sed -i "s/^access_key = .*/access_key = ${S3_ACCESS_KEY}/" rgw_s3_client.py
→ S3_SECRET_KEY=$(kubectl exec ${RGW_POD_NAME} -- radosgw-admin user info --uid=rgwuser | awk '/secret_key/ {print $2}' | sed "s/\"/'/g")
→ echo ${S3_SECRET_KEY}
'kxGX71IR0KmFLnoph1gFrmVCzUbzRqrNtzOeLVgA'
→ sed -i "s/^secret_key = .*/secret_key = ${S3_SECRET_KEY}/" rgw_s3_client.py
→ sed -i "s/host = .*,/host = '${NODE_PUBLIC_IP}',/" rgw_s3_client.py
→ sed -i "s/port = .*,/port = ${RGW_NODE_PORT},/" rgw_s3_client.py
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
my-s3-test-bucket       2017-01-23T18:26:53.873Z
http://104.196.229.155:31977/my-s3-test-bucket/hello.txt
http://104.196.229.155:31977/my-s3-test-bucket/secret_plans.txt?Signature=l4t9Y9Zzg9WoQ%2BUY0IBE9mBSzIQ%3D&Expires=1485199616&AWSAccessKeyId=C18XSK449ZTBJJ2BPGF7
→ curl http://104.196.229.155:31977/my-s3-test-bucket/hello.txt
Hello World!
→ curl 'http://104.196.229.155:31977/my-s3-test-bucket/secret_plans.txt?Signature=l4t9Y9Zzg9WoQ%2BUY0IBE9mBSzIQ%3D&Expires=1485199616&AWSAccessKeyId=C18XSK449ZTBJJ2BPGF7'
My secret plans!
```

### CephFS and RBD

#### Install Ceph and RBD utilities on all worker nodes

The Kubernetes `kubelet` shells out to system utilities to mount Ceph volumes. This means that every worker node that could potentially run pods requiring the mounting of Ceph volumes must have these utilities installed. We can go ahead and install all of the necessary Ceph and RBD utilities since all of our nodes are using Ubuntu 16.04 Xenial. Therefore, for Debian-based distros we install the following:

```
apt-get install ceph-fs-common ceph-common
```

This can be achieved programatically by issuing the below commands using the same `NUM_WORKERS` variable that was created earlier:

```
for i in $(eval echo "{0..$(expr ${NUM_WORKERS} - 1)}"); do gcloud compute ssh worker${i} --command "sudo apt-get update" & done; wait
for i in $(eval echo "{0..$(expr ${NUM_WORKERS} - 1)}"); do gcloud compute ssh worker${i} --command "sudo apt-get install -y ceph-fs-common ceph-common" & done; wait
```

#### Mounting CephFS in a pod

First we must add the admin client key to our current `ceph` namespace. However, this admin client key has already been added by the `create_secrets.sh` script that generated and created the secrets so we can skip this step now.

Next, because Kubernetes installs do not configure the nodes’ `resolv.conf` files to use the cluster DNS by default, we cannot rely on using the Ceph Monitor DNS names in the following tests. This is a known issue and you can get more details in the **Known Issues** section at [http://kubernetes.io/docs/admin/dns/](http://kubernetes.io/docs/admin/dns/).

Instead, we'll have to manually update the test resouces with the Ceph Monitor IP addresses. To get a ceph-mon pod IP address we can issue:

```
→ MON_POD_IP=$(kubectl get pods --selector="app=ceph,daemon=mon" --output=template --template="{{with index .items 0}}{{.status.podIP}}{{end}}")
→ echo ${MON_POD_IP}
10.200.2.4
```
We then modify `ceph-cephfs-test.yaml` to use this ceph-mon pod IP address:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" ceph-cephfs-test.yaml
```

We're now ready to create the cephfs test:

```
→ kubectl create -f ceph-cephfs-test.yaml
pod "ceph-cephfs-test" created
```

Verify the pod is up and running:

```
→ kubectl get pod -l test=cephfs -o wide --watch
NAME               READY     STATUS    RESTARTS   AGE       IP           NODE
ceph-cephfs-test   1/1       Running   0          6s        10.200.4.5   worker4
```

Once the pod is up and running you should be able to see the filesystem mounted as a `ceph` filesystem type:

```
→ kubectl exec ceph-cephfs-test -- df -hT | grep ceph
10.200.2.4:6789:/    ceph            1.3T     54.7G      1.3T   4% /mnt/cephfs
```

##### Testing CephFS mount

A simple test we can perform is to write a test file and then read it back:

```
→ kubectl exec ceph-cephfs-test -- sh -c "echo Hello CephFS World! > /mnt/cephfs/testfile.txt"
→ kubectl exec ceph-cephfs-test -- cat /mnt/cephfs/testfile.txt
Hello CephFS World!
```

#### Mounting Ceph RBD in a pod

First we have to create an RBD volume. We already have a Ceph Monitor pod name assigned to the `MON_POD_NAME` variable from previously so we'll re-use it:

```
→ kubectl exec ${MON_POD_NAME} -- rbd create ceph-rbd-test --size 20G
→ kubectl exec ${MON_POD_NAME} -- rbd info ceph-rbd-test
rbd image 'ceph-rbd-test':
        size 20480 MB in 5120 objects
        order 22 (4096 kB objects)
        block_name_prefix: rbd_data.10482ae8944a
        format: 2
        features: layering
        flags:
```

The same caveats apply for RBDs as Ceph FS volumes so we edit the pod IP accordingly:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" ceph-rbd-test.yaml
```

Once you're set just create the resource and check its status:

```
→ kubectl create -f ceph-rbd-test.yaml
pod "ceph-rbd-test" created
→ kubectl get pods -l test=rbd -o wide --watch
NAME            READY     STATUS              RESTARTS   AGE       IP        NODE
ceph-rbd-test   0/1       ContainerCreating   0          3s        <none>    worker4
NAME            READY     STATUS    RESTARTS   AGE       IP           NODE
ceph-rbd-test   1/1       Running   0          5s        10.200.4.6   worker4
```

Again you should see your `ext4` RBD mount, but with 20 GB size:

```
→ kubectl exec ceph-rbd-test -- df -hT | grep rbd
/dev/rbd0            ext4           19.6G     43.9M     18.5G   0% /mnt/cephrbd
```

##### Testing RBD mount

We can do the same simple test to write a test file and then read it back:

```
→ kubectl exec ceph-rbd-test -- sh -c "echo Hello Ceph RBD World! > /mnt/cephrbd/testfile.txt"
→ kubectl exec ceph-rbd-test -- cat /mnt/cephrbd/testfile.txt
Hello Ceph RBD World!
```

### Persistent Volume Claim with Static Provisioning

#### Rados Block Device (RBD)

For persistent volume claims with static provisioning we need to add the Ceph admin keyring as a Kubernetes secret so that our persistent volume resource will have the necessary permissions to create the persistent volume. The name given to the Ceph admin keyring secret must match the name given to the secret in the persistent volume resource we create later. For now let's create the secret and use the same `MON_POD_NAME` we set previously:

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
        block_name_prefix: rbd_data.104d238e1f29
        format: 2
        features: layering
        flags:
```

We're almost ready to create the persistent volume resource but we need to modify the Ceph MON DNS to use the IP address. As previously mentioned, this is because Kubernetes installs do not configure the nodes’ `resolv.conf` files to use the cluster DNS by default, so we cannot rely on using the Ceph Monitor DNS names. This is a known issue and you can get more details in the **Known Issues** section at [http://kubernetes.io/docs/admin/dns/](http://kubernetes.io/docs/admin/dns/).

Using the same `MON_POD_IP` we set earlier issue the command:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" rbd-pv.yaml
```

Create the persistent volume and check its status:

```
→ kubectl create -f rbd-pv.yaml
persistentvolume "ceph-rbd-pv" created
→ kubectl get pv
NAME          CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
ceph-rbd-pv   10Gi       RWO           Recycle         Available                       4s
→ kubectl describe pv
Name:           ceph-rbd-pv
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
    CephMonitors:       [10.200.2.4:6789]
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
persistentvolumeclaim "ceph-rbd-pv-claim" created
→ kubectl get pvc
NAME                STATUS    VOLUME        CAPACITY   ACCESSMODES   AGE
ceph-rbd-pv-claim   Bound     ceph-rbd-pv   10Gi       RWO           3s
→ kubectl describe pvc
Name:           ceph-rbd-pv-claim
Namespace:      ceph
StorageClass:
Status:         Bound
Volume:         ceph-rbd-pv
Labels:         <none>
Capacity:       10Gi
Access Modes:   RWO
No events.
```

Lastly, we create a test pod to utilize the persistent volume claim.

```
→ kubectl create -f rbd-pvc-pod.yaml
pod "ceph-rbd-pv-pod1" created
→ kubectl get pod -l test=rbd-pvc-pod -o wide --watch
NAME               READY     STATUS              RESTARTS   AGE       IP        NODE
ceph-rbd-pv-pod1   0/1       ContainerCreating   0          2s        <none>    worker0
NAME               READY     STATUS    RESTARTS   AGE       IP           NODE
ceph-rbd-pv-pod1   1/1       Running   0          6s        10.200.0.5   worker0
```

Once the pod is running we can display the RBD PVC mount with 10 GB size:

```
→ kubectl exec ceph-rbd-pv-pod1 -- df -hT | grep rbd
/dev/rbd0            ext4            9.7G     22.5M      9.2G   0% /mnt/ceph-rbd-pvc
```

Make sure we can do a simple test to write a test file and then read it back:

```
→ kubectl exec ceph-rbd-pv-pod1 -- sh -c "echo Hello RBD PVC World! > /mnt/ceph-rbd-pvc/testfile.txt"
→ kubectl exec ceph-rbd-pv-pod1 -- cat /mnt/ceph-rbd-pvc/testfile.txt
Hello RBD PVC World!
```

And that shows we've set up an RBD persistent volume claim with static provisioning that can be consumed by a pod!

#### Ceph Filesystem (CephFS)

We will be using the same `MON_POD_IP` and `ceph-admin-secret` that were created above so make sure these are set before continuing.

Using the same `MON_POD_IP` we set earlier issue the command:

```
sed -i "s/ceph-mon.ceph/${MON_POD_IP}/" cephfs-pv.yaml
```

Create the persistent volume and check its status:

```
→ kubectl create -f cephfs-pv.yaml
persistentvolume "cephfs-pv" created
→ kubectl get pv cephfs-pv
NAME        CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
cephfs-pv   10Gi       RWX           Recycle         Available                       4s
→ kubectl describe pv cephfs-pv
Name:           cephfs-pv
Labels:         <none>
StorageClass:
Status:         Available
Claim:
Reclaim Policy: Recycle
Access Modes:   RWX
Capacity:       10Gi
Message:
Source:
No events.
```

Next we create the persistent volume claim:

```
→ kubectl create -f cephfs-pv-claim.yaml
persistentvolumeclaim "cephfs-pv-claim" created
→ kubectl get pvc cephfs-pv-claim
NAME              STATUS    VOLUME      CAPACITY   ACCESSMODES   AGE
cephfs-pv-claim   Bound     cephfs-pv   10Gi       RWX           4s
→ kubectl describe pvc cephfs-pv-claim
Name:           cephfs-pv-claim
Namespace:      ceph
StorageClass:
Status:         Bound
Volume:         cephfs-pv
Labels:         <none>
Capacity:       10Gi
Access Modes:   RWX
No events.
```

Lastly, we create a test pod to utilize the persistent volume claim.

```
→ kubectl create -f cephfs-pvc-pod.yaml
pod "cephfs-pv-pod1" created
→ kubectl get pod -l test=cephfs-pvc-pod -o wide --watch
NAME             READY     STATUS    RESTARTS   AGE       IP           NODE
cephfs-pv-pod1   1/1       Running   0          3s        10.200.9.4   worker9
```

Once the pod is running we can display the CephFS PVC mount:

```
→ kubectl exec cephfs-pv-pod1 -- df -hT | grep ceph
10.200.2.4:6789:/    ceph            1.3T     55.5G      1.3T   4% /mnt/cephfs-pvc
```

Make sure we can do a simple test to write a test file and then read it back:

```
→ kubectl exec cephfs-pv-pod1 -- sh -c "echo Hello CephFS PVC World! > /mnt/cephfs-pvc/testfile.txt"
→ kubectl exec cephfs-pv-pod1 -- cat /mnt/cephfs-pvc/testfile.txt
Hello CephFS PVC World!
```

And that shows we've set up a CephFS persistent volume claim with static provisioning that can be consumed by a pod!

### Persistent Volume Claim with Dynamic Provisioning

#### Rados Block Device (RBD)

##### Preqrequisites
- Kubernetes version 1.5.1
- Ceph and RBD utilities installed on:
    - Controller nodes
    - Any worker nodes hosting Ceph Monitor pods

Before we proceed, in order for this to work the `rbd` command line utility must be installed on any host/container that `kube-controller-manager` or `kubelet` is running on. Note that we've already installed the necessary Ceph and RBD utilities on the worker nodes, so let's do the same for the controller nodes using the `NUM_CONTROLLERS` variable created earlier:

```
for i in $(eval echo "{0..$(expr ${NUM_CONTROLLERS} - 1)}"); do gcloud compute ssh controller${i} --command "sudo apt-get update" & done; wait
for i in $(eval echo "{0..$(expr ${NUM_CONTROLLERS} - 1)}"); do gcloud compute ssh controller${i} --command "sudo apt-get install -y ceph-fs-common ceph-common" & done; wait
```

For persistent volume claims with dynamic provisioning we need to add the Ceph admin keyring as a Kubernetes secret to the same namespace that is defined in our StorageClass resource so that it will have the necessary permissions to create the dynamically provisioned volume. For this example we'll use `kube-system` as the namespace. Also, the name given to the Ceph secret admin keyring must match the name given to the admin secret in the StorageClass resource we create later. For now let's create the secret and use the same `MON_POD_NAME` we set previously:

```
→ ADMIN_KEYRING=$(kubectl exec ${MON_POD_NAME} -- ceph auth get client.admin 2>&1 | awk '/key =/ {print$3}')
→ kubectl create secret generic ceph-secret-admin --from-literal=key="${ADMIN_KEYRING}" --namespace=kube-system --type=kubernetes.io/rbd
secret "ceph-secret-admin" created
→ kubectl get secret ceph-secret-admin --namespace kube-system
NAME                TYPE                DATA      AGE
ceph-secret-admin   kubernetes.io/rbd   1         5s
```

Now we create the RBD StorageClass named `slow` using the `kubernetes.io/rbd` provisioner. We must also specify a comma separated list of `ceph-mon` pod IPs in order for the StorageClass to access the Ceph monitors:

```
→ MON_POD_IPS=$(kubectl get pods -l daemon=mon -o wide | awk '/ceph-mon/ {print $6}')
→ echo ${MON_POD_IPS}
10.200.2.4 10.200.5.3 10.200.6.5
→ for i in ${MON_POD_IPS}; do MONITORS_CSV="${MONITORS_CSV}${i}:6789,"; done; MONITORS_CSV=$(echo ${MONITORS_CSV} | sed 's/,$//')
→ echo ${MONITORS_CSV}
10.200.2.4:6789,10.200.5.3:6789,10.200.6.5:6789
→ sed -i "s/monitors: .*/monitors: ${MONITORS_CSV}/" rbd-storage-class.yaml
→ grep 'monitors: .*' rbd-storage-class.yaml
    monitors: 10.200.2.4:6789,10.200.5.3:6789,10.200.6.5:6789
→ kubectl create -f rbd-storage-class.yaml
storageclass "slow" created
→ kubectl describe storageclass
Name:           slow
IsDefaultClass: No
Annotations:    <none>
Provisioner:    kubernetes.io/rbd
Parameters:     adminId=admin,adminSecretName=ceph-secret-admin,adminSecretNamespace=kube-system,monitors=10.200.2.4:6789,10.200.5.3:6789,10.200.6.5:6789,pool=kube,userId=kube,userSecretName=ceph-secret-user
No events.
```

The `kube-controller-manager` is now able to provision storage, but we still need to be able to map the RBD volume to a node. Mapping should be done with a non-privileged key. You can use an existing user in your Ceph cluster that you can retrieve with `ceph auth list`, but for this example we'll just create a new user and pool to avoid confusion. This new user and pool should match the names provided in the StorageClass resource we created previously, namely `kube` using the `ceph-secret-user` secret name. Let's do that now:

```
→ kubectl exec ${MON_POD_NAME} -- ceph osd pool create kube 64
pool 'kube' created
→ kubectl exec ${MON_POD_NAME} -- ceph auth get-or-create client.kube mon 'allow r' osd 'allow rwx pool=kube'
[client.kube]
        key = AQAFaIZYqmOiDRAAk1m4IzlVokdtNu06ISkQ0g==
```

Now we'll create a secret using this new user and key. Note that this user secret will need to be created in every namespace where you intend to consume RBD volumes provisioned by our StorageClass resource. For this example, we'll just create the secret in our current context's namespace, `ceph`.

```
→ KUBE_KEYRING=$(kubectl exec ${MON_POD_NAME} -- ceph auth get client.kube 2>&1 | awk '/key =/ {print$3}')
→ echo ${KUBE_KEYRING}
AQAFaIZYqmOiDRAAk1m4IzlVokdtNu06ISkQ0g==
→ kubectl create secret generic ceph-secret-user --from-literal=key="${KUBE_KEYRING}" --type=kubernetes.io/rbd
secret "ceph-secret-user" created
```

Okay, we're ready to provision and use RBD storage. To do that we'll create a Persistent Volume Claim in our `ceph` namespace that will use the StorageClass configuration.

```
→ kubectl create -f rbd-dyn-pv-claim.yaml
persistentvolumeclaim "ceph-rbd-dyn-pv-claim" created
```

You should then see a PVC bound to a dynamically provisioned PV using RBD storage:

```
→ kubectl describe pvc ceph-rbd-dyn-pv-claim
Name:           ceph-rbd-dyn-pv-claim
Namespace:      ceph
StorageClass:   slow
Status:         Bound
Volume:         pvc-8b09964d-e1ab-11e6-990f-42010af0000b
Labels:         <none>
Capacity:       3Gi
Access Modes:   RWO
No events.
→ kubectl describe pv pvc
Name:           pvc-8b09964d-e1ab-11e6-990f-42010af0000b
Labels:         <none>
StorageClass:   slow
Status:         Bound
Claim:          ceph/ceph-rbd-dyn-pv-claim
Reclaim Policy: Delete
Access Modes:   RWO
Capacity:       3Gi
Message:
Source:
    Type:               RBD (a Rados Block Device mount on the host that shares a pod's lifetime)
    CephMonitors:       [10.200.2.4:6789 10.200.5.3:6789 10.200.6.5:6789]
    RBDImage:           kubernetes-dynamic-pvc-8b1189fc-e1ab-11e6-9aff-42010af0000a
    FSType:
    RBDPool:            kube
    RadosUser:          kube
    Keyring:            /etc/ceph/keyring
    SecretRef:          &{ceph-secret-user}
    ReadOnly:           false
No events.

```

With our storage dynamically provisioned, let's create a test pod to consume the PVC:

```
→ kubectl create -f rbd-dyn-pvc-pod.yaml
pod "ceph-rbd-dyn-pv-pod1" created
→ kubectl exec ceph-rbd-dyn-pv-pod1 -- df -h | grep rbd
/dev/rbd0                 2.9G      4.5M      2.7G   0% /mnt/ceph-dyn-rbd-pvc
```

That shows our pod has an RBD mount with a storage capacity equal to the size requested in the PVC i.e. `3Gi`.

Lastly, make sure we can do a simple test to write a test file and then read it back:

```
→ kubectl exec ceph-rbd-dyn-pv-pod1 -- sh -c "echo Hello Dynamically Provisioned PVC World! > /mnt/ceph-dyn-rbd-pvc/testfile.txt"
→ kubectl exec ceph-rbd-dyn-pv-pod1 -- cat /mnt/ceph-dyn-rbd-pvc/testfile.txt
Hello Dynamically Provisioned PVC World!
```

And that shows we've set up an RBD persistent volume claim with dynamic provisioning that can be consumed by a pod!

# Video Demonstration

A recorded video demonstrating a containerized Ceph deployment on a Kubernetes cluster running on Google Compute Engine:

[![Demo Ceph deployment on Kubernetes with GCE](https://img.youtube.com/vi/ic38-19wIGY/0.jpg)](https://youtu.be/ic38-19wIGY "Demo Ceph deployment on Kubernetes with GCE")
