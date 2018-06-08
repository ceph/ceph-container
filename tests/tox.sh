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
    sudo yum -y install https://centos7.iuscommunity.org/ius-release.rpm
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

rm -rf "$WORKSPACE"/ceph-ansible || true
git clone -b "$CEPH_ANSIBLE_BRANCH" --single-branch https://github.com/ceph/ceph-ansible.git ceph-ansible

if [[ "$CEPH_ANSIBLE_BRANCH" == 'stable-2.2' ]] || [[ "$CEPH_ANSIBLE_BRANCH" == 'stable-3.0' ]]; then
  REQUIREMENTS=requirements2.2.txt
else
  REQUIREMENTS=requirements2.4.txt
fi

pip install -r "$TOXINIDIR"/ceph-ansible/tests/"$REQUIREMENTS"

bash "$WORKSPACE"/travis-builds/purge_cluster.sh
# XXX purge_cluster only stops containers, it doesn't really remove them so try to
# remove them for real
containers_to_remove=$(sudo docker ps -a -q)

if [ "${containers_to_remove}" ]; then
  sudo docker rm -f "$@" "${containers_to_remove}" || echo failed to remove containers
fi

cd "$WORKSPACE"

# build everything that was touched to make sure build succeeds
mapfile -t FLAVOR_ARRAY < <(sudo make flavors.modified)

if [[ "${#FLAVOR_ARRAY[@]}" -eq "0" ]]; then
  echo "The ceph-container code has not changed."
  echo "Nothing to test here."
  echo "SUCCESS"
  exit 0
fi

if [[ "${#FLAVOR_ARRAY[@]}" -eq "1" ]]; then
  FLAVOR="${FLAVOR_ARRAY[0]}"
else
  # if more than one release/distro is impacted
  # then we test the latest stable release of Ceph in priority
  FLAVOR="mimic,centos,7"
fi

CURRENT_CEPH_STABLE_RELEASE="$(echo $FLAVOR|awk -F ',' '{ print $1}')"

# CEPH_STABLE_RELEASE is an info passed by the CI (see tox.ini)
# if CEPH_STABLE_RELEASE does not match CURRENT_CEPH_STABLE_RELEASE then CEPH_STABLE_RELEASE wins
# so we will build the desired CEPH_STABLE_RELEASE since the current patch didn't change the Ceph version
# Since we test all the Ceph releases, we will always test the impacted one
if [[ "$CEPH_STABLE_RELEASE" != "$CURRENT_CEPH_STABLE_RELEASE" ]]; then
  FLAVOR="$CEPH_STABLE_RELEASE,centos,7"
fi

echo "Building flavor $FLAVOR"
make_output=$(sudo make FLAVORS="$FLAVOR" stage) # Run staging to get DAEMON_IMAGE name
daemon_image=$(echo "${make_output}" | grep " DAEMON_IMAGE ") # Find DAEMON_IMAGE line
daemon_image="${daemon_image#*DAEMON_IMAGE*: }" # Remove DAEMON_IMAGE from beginning
daemon_image="$(echo "${daemon_image}" | tr -s ' ')" # Remove whitespace
sudo make FLAVORS="$FLAVOR" build.parallel

# start a local docker registry
sudo docker run -d -p 5000:5000 --restart=always --name registry registry:2
# add the image we just built to the registry
sudo docker tag "${daemon_image}" localhost:5000/ceph/daemon:"$CEPH_STABLE_RELEASE"-latest
# this avoids a race condition between the tagging and the push
# which causes this to sometimes fail when run by jenkins
sleep 1
sudo docker --debug push localhost:5000/ceph/daemon:"$CEPH_STABLE_RELEASE"-latest

cd "$CEPH_ANSIBLE_SCENARIO_PATH"
vagrant up --no-provision --provider="$VAGRANT_PROVIDER"

bash "$TOXINIDIR"/ceph-ansible/tests/scripts/generate_ssh_config.sh "$CEPH_ANSIBLE_SCENARIO_PATH"

export ANSIBLE_SSH_ARGS="-F $CEPH_ANSIBLE_SCENARIO_PATH/vagrant_ssh_config"


# runs a playbook to configure nodes for testing
ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/tests/setup.yml
ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/ceph-ansible/site-docker.yml.sample --extra-vars="ceph_stable_release=$CEPH_STABLE_RELEASE ceph_docker_image_tag=$CEPH_STABLE_RELEASE-latest ceph_docker_registry=$REGISTRY_ADDRESS fetch_directory=$CEPH_ANSIBLE_SCENARIO_PATH/fetch"

ansible-playbook -vv -i "$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/ceph-ansible/tests/functional/setup.yml

testinfra -n 4 --sudo -v --connection=ansible --ansible-inventory="$CEPH_ANSIBLE_SCENARIO_PATH"/hosts "$TOXINIDIR"/ceph-ansible/tests/functional/tests

# teardown
#################################################################################
bash "$TOXINIDIR"/tests/teardown.sh
