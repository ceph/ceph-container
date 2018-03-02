# Introspect disks available on the machines using a container

The idea is to widely deploy this container on the hosts that should become storage nodes.
Do we need a label for that?

The container will need the following privileges otherwise will fail: '--privileged=true -v /dev/:/dev/'
It will:
  * look for the devices without a partition available
  * store the list in a text file
  * send that list to a configmaps

Configmaps are sent using the following name so they should be easily recognizable by the container: `<node_name>-disks`.

Later, we run the k8s template that should iterate through the list of devices of a given configmaps.
The tricky part is to build the relationship between the list and where the container will run since the configmaps are named after the hostname...
