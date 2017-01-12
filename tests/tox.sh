#!/bin/bash -ex

# Proxy script from tox. This is an intermediate script so that we can setup
# the environment properly then call ceph-ansible for testing, and finally tear
# down, while keeping tox features of simplicity and combinatorial confgiruation.
#
# NOTE: Do not run this script directly as it depends on a few environment
# variables that tox will set, like ceph-ansible's scenario path

# setup
#################################################################################
# XXX this should probably not install system dependencies like this, since now
# it means we are tied to an apt-get distro
sudo apt-get install -y --force-yes docker.io
sudo apt-get install -y --force-yes xfsprogs
git clone -b $CEPH_ANSIBLE_BRANCH --single-branch https://github.com/ceph/ceph-ansible.git ceph-ansible
pip install -r $TOXINIDIR/ceph-ansible/tests/requirements.txt

# pull requests tests should never have these directories here, but branches
# do, so for the build scripts to work correctly, these neeed to be removed
# XXX It requires sudo because these will appear with `root` ownership
rm -rf "$WORKSPACE"/{daemon,demo,base}

bash "$WORKSPACE"/travis-builds/purge_cluster.sh
# XXX purge_cluster only stops containers, it doesn't really remove them so try to
# remove them for real
containers_to_remove=$(docker ps -a -q)

if [ "${containers_to_remove}" ]; then
    docker rm -f $@ ${containers_to_remove} || echo failed to remove containers
fi

bash "$WORKSPACE"/travis-builds/build_imgs.sh

# test
#################################################################################

# TODO: get the output image from build_imgs.sh to pass onto ceph-ansible

# run vagrant and ceph-ansible tests
#################################################################################
cd "$CEPH_ANSIBLE_SCENARIO_PATH"
vagrant up --no-provision --provider=$VAGRANT_PROVIDER

bash $TOXINIDIR/ceph-ansible/tests/scripts/generate_ssh_config.sh $CEPH_ANSIBLE_SCENARIO_PATH

export ANSIBLE_SSH_ARGS="-F $CEPH_ANSIBLE_SCENARIO_PATH/vagrant_ssh_config"

ansible-playbook -vv -i $CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/ceph-ansible/site-docker.yml.sample --extra-vars="ceph_docker_dev_image=true fetch_directory=$CEPH_ANSIBLE_SCENARIO_PATH/fetch"

ansible-playbook -vv -i $CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/ceph-ansible/tests/functional/setup.yml

testinfra -n 4 --sudo -v --connection=ansible --ansible-inventory=$CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/ceph-ansible/tests/functional/tests

# teardown
#################################################################################
cd $CEPH_ANSIBLE_SCENARIO_PATH
vagrant destroy --force
cd $WORKSPACE
