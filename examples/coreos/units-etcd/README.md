Deploy Ceph in Containers using Fleet with Etcd Support Example
===============================================================

In this example, the configs (/etc/ceph/*) are created when the first Ceph monitor boots up and stored in Etcd cluster. When new node joins the Ceph cluster, the configs are pulled automatically from Etcd servers. So manual distribution of the config files can be avoided. In order to examine the generated config file, you will need to login to the running container using `docker exec -it CONTAINER bash`.

Those units assume an Etcd proxy/server is running on localhost. If not, please change KV_IP to the Etcd cluster and use KV_PORT for non-default Etcd port.

It is also possible using Consul, but such a deployment is not tested yet. 

Deploy Units with Fleet
-----------------------

# Monitors
Monitors have to be deployed first, before any other components.

```bash
fleetctl start ceph-mon@1
fleetctl start ceph-mon@2
...
```

# OSDs

```bash
fleetctl start ceph-osd@1
fleetctl start ceph-osd@2
...
```

# MDS 

```bash
fleetctl start ceph-mds@1
fleetctl start ceph-mds@2
...
```

# RGW 

```bash
fleetctl start ceph-rgw@1
...
```

You can change the machine metadata selector (MachineMetadata, Global) to match your deployment requirements in the unit files under X-Fleet section.
