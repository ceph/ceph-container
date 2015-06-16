Usage
=====

Create a file called `ceph-mon.json` with the repository content.
Eventually run the pod like so:

`kubectl create -f mon.json`

Check the status of the pod:

```
$ kubectl get pod
POD              IP            CONTAINER(S)   IMAGE(S)      HOST                  LABELS          STATUS    CREATED      MESSAGE
ceph-mon-5ceys   172.17.0.13                                127.0.0.1/127.0.0.1   name=frontend   Running   49 minutes
                               ceph-mon       ceph-daemon                                         Running   49 minutes
```

You can check the logs using: `kubectl log ceph-mon-5ceys`
