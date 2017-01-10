#!/bin/bash -ex

# Proxy script from tox. This is an intermediate script so that we can setup
# the environment properly then call ceph-ansible for testing, and finally tear
# down, while keeping tox features of simplicity and combinatorial confgiruation.
#
# NOTE: Do not run this script directly as it depends on a few environment
# variables that tox will set, like ceph-ansible's scenario path

# setup
#################################################################################
git clone -b $CEPH_ANSIBLE_BRANCH --single-branch https://github.com/ceph/ceph-ansible.git ceph-ansible
pip install -r $TOXINIDIR/ceph-ansible/tests/requirements.txt

# test
#################################################################################

# vars
#################################################################################
export ANSIBLE_SSH_ARGS=-F $CEPH_ANSIBLE_SCENARIO_PATH/vagrant_ssh_config

# run vagrant and ceph-ansible tests
#################################################################################
cd "$CEPH_ANSIBLE_SCENARIO_PATH"
vagrant up --no-provision --provider=$VAGRANT_PROVIDER
bash $TOXINIDIR/tests/scripts/generate_ssh_config.sh $CEPH_ANSIBLE_SCENARIO_PATH

ansible-playbook -vv -i $CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/ceph-ansible/site-docker.yml.sample --extra-vars="fetch_directory=$CEPH_ANSIBLE_SCENARIO_PATH/fetch"

ansible-playbook -vv -i $CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/ceph-ansible/tests/functional/setup.yml

testinfra -n 4 --sudo -v --connection=ansible --ansible-inventory=$CEPH_ANSIBLE_SCENARIO_PATH/hosts $TOXINIDIR/ceph-ansible/tests/functional/tests

# teardown
#################################################################################
cd $CEPH_ANSIBLE_SCENARIO_PATH
vagrant destroy --force
cd $WORKSPACE
