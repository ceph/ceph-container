# Ceph on CoreOS for Kubernetes

This project enables running Ceph systems on Kubernetes on CoreOS and accessing Ceph resources via Kubernetes. Installation can occur in several ways:

- Manually execute the image built by the included Dockerfile:

  ```
  sudo /usr/bin/docker run --rm -v /opt/bin:/opt/bin quay.io/coffeepac/ceph-install
  ```

- Modify `install-job.yaml` to have at least one job per node in the kubernetes cluster. This is only a best effort as Kubernetes may schedule several of the pods for a single high performing node

  ```
  kubectl create -f install-job.yaml
  ```

  This currently pulls the latest tag which will sleep for 30d after the install is complete. Should have a separate tag for the job

- Install the daemon-set. this will install the required ceph utilities once on each node and then sleep for 30 days. Its not ideal but it will also install the ceph components to any future node.

  ```
  kubectl create -f install-ds.yaml
  ```

  This assumes a 'ceph' namespace exists. If not you'll have to create one:

  ```
  kubectl create namespace ceph
  ```

  Once the tools are installed you can follow the kubernetes example.

## Additional Kubenetes configuration

There are two additional pieces of configuration that have to happen:

- The kubelet and apiserver need to be run with the flag `allow-privileged`
- The kubelet's need to have the following added to the Unit file:

  ```
  Environment=PATH=/opt/bin/:/usr/bin/:/usr/sbin:$PATH
  ```
