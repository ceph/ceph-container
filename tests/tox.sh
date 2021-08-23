#!/bin/bash -ex

set -ex

# Proxy script from tox. This is an intermediate script so that we can setup
# the environment properly then call ceph-ansible for testing, and finally tear
# down, while keeping tox features of simplicity and combinatorial confgiruation.
#
# NOTE: Do not run this script directly as it depends on a few environment
# variables that tox will set, like ceph-ansible's scenario path

# setup
#################################################################################
# If WORKSPACE is undefined, set it to $TOXINIDIR
echo "${WORKSPACE:=$TOXINIDIR}"

# Write down a couple environment variables, for use in teardown
OUR_TOX_VARS=$WORKSPACE/.tox_vars
rm -f "$OUR_TOX_VARS"
cat > "$OUR_TOX_VARS" << EOF
export WORKSPACE=$WORKSPACE
export CEPH_ANSIBLE_SCENARIO_PATH=$CEPH_ANSIBLE_SCENARIO_PATH
EOF

# Check distro and install deps
if command -v apt-get &>/dev/null; then
  sudo apt-get install -y --force-yes docker.io xfsprogs python3.6
  sudo ln -sf "$(command -v python3.6)" /usr/bin/python3
else
  sudo yum install -y docker xfsprogs
  if ! command -v python3.6 &>/dev/null; then
    sudo yum -y groupinstall development
    sudo yum -y install https://repo.ius.io/ius-release-el7.rpm
    sudo yum -y install python36u
  fi
  sudo ln -sf "$(command -v python3.6)" /usr/bin/python3

  if ! systemctl status docker >/dev/null; then
    # daemon doesn't start automatically after being installed
    sudo systemctl restart docker
  fi
  # Allow running `docker` without sudo
  sudo chgrp "$(whoami)" /var/run/docker.sock
fi

if [ -n "${REGISTRY_USERNAME}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
  docker login -u "${REGISTRY_USERNAME}" -p "${REGISTRY_PASSWORD}" "${REGISTRY}"
fi

rm -rf "$WORKSPACE"/ceph-ansible || true
git clone -b "$CEPH_ANSIBLE_BRANCH" --single-branch https://github.com/ceph/ceph-ansible.git ceph-ansible

pip install -r "$TOXINIDIR"/ceph-ansible/tests/requirements.txt

bash "$WORKSPACE"/travis-builds/purge_cluster.sh
# XXX purge_cluster only stops containers, it doesn't really remove them so try to
# remove them for real
containers_to_remove=$(docker ps -a -q)

if [ "${containers_to_remove}" ]; then
  docker rm -f "$@" "${containers_to_remove}" || echo failed to remove containers
fi

cd "$WORKSPACE"
# we test the latest stable release of Ceph in priority
FLAVOR="master,centos,8"

# build everything that was touched to make sure build succeeds
mapfile -t FLAVOR_ARRAY < <(make flavors.modified)

if [[ "$NIGHTLY" != 'TRUE' ]]; then
  if [[ "${#FLAVOR_ARRAY[@]}" -eq "0" ]]; then
    echo "The ceph-container code has not changed."
    echo "Nothing to test here."
    echo "SUCCESS"
    make clean.all
    exit 0
  fi

  if [[ "${#FLAVOR_ARRAY[@]}" -eq "1" ]]; then
    FLAVOR="${FLAVOR_ARRAY[0]}"
  fi
fi

echo "Building flavor $FLAVOR"
make_output=$(make FLAVORS="$FLAVOR" stage) # Run staging to get DAEMON_IMAGE name
daemon_image=$(echo "${make_output}" | grep " DAEMON_IMAGE ") # Find DAEMON_IMAGE line
daemon_image="${daemon_image#*DAEMON_IMAGE*: }" # Remove DAEMON_IMAGE from beginning
daemon_image="$(echo "${daemon_image}" | tr -s ' ')" # Remove whitespace
make FLAVORS="$FLAVOR" BASEOS_REGISTRY="${REGISTRY}/centos" BASEOS_REPO="centos" build.parallel

# start a local docker registry
docker run -d -p 5000:5000 --restart=always --name registry registry:2
# add the image we just built to the registry
docker tag "${daemon_image}" localhost:5000/ceph/daemon:latest-master
# this avoids a race condition between the tagging and the push
# which causes this to sometimes fail when run by jenkins
sleep 1
docker --debug push localhost:5000/ceph/daemon:latest-master

cd "$CEPH_ANSIBLE_SCENARIO_PATH"
bash "$TOXINIDIR"/ceph-ansible/tests/scripts/vagrant_up.sh --no-provision --provider="$VAGRANT_PROVIDER"

bash "$TOXINIDIR"/ceph-ansible/tests/scripts/generate_ssh_config.sh "$CEPH_ANSIBLE_SCENARIO_PATH"

export ANSIBLE_SSH_ARGS="-F $CEPH_ANSIBLE_SCENARIO_PATH/vagrant_ssh_config -o ControlMaster=auto -o ControlPersist=600s -o PreferredAuthentications=publickey"

# runs a playbook to configure nodes for testing
ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/tests/setup.yml --extra-vars="ceph_docker_registry=$REGISTRY_ADDRESS"
if [[ $CEPH_ANSIBLE_SCENARIO_PATH =~ "all_daemons" ]]; then
  ANSIBLE_PLAYBOOK_ARGS=(--limit 'osds:!osd2')
fi
ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/ceph-ansible/tests/functional/lvm_setup.yml "${ANSIBLE_PLAYBOOK_ARGS[@]}"
ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/ceph-ansible/tests/functional/setup.yml
ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/ceph-ansible/site-container.yml.sample --extra-vars="ceph_docker_image_tag=latest-master ceph_docker_registry=$REGISTRY_ADDRESS ceph_docker_image=ceph/daemon"

py.test --reruns 20 --reruns-delay 3 -n 8 --sudo -v --connection=ansible --ansible-inventory="$CEPH_ANSIBLE_SCENARIO_PATH"/hosts --ssh-config="$CEPH_ANSIBLE_SCENARIO_PATH"/vagrant_ssh_config "$TOXINIDIR"/ceph-ansible/tests/functional/tests

# teardown
#################################################################################
cd "$WORKSPACE"
make clean.all
bash "$TOXINIDIR"/tests/teardown.sh
