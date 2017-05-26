#!/usr/bin/env python
"""
Proxy script from tox. This is an intermediate script so that we can setup
the environment properly then call ceph-ansible for testing, and finally tear
down, while keeping tox features of simplicity and combinatorial confgiruation.

NOTE: Do not run this script directly as it depends on a few environment
variables that tox will set, like ceph-ansible's scenario path
"""
import logging
import os
import pwd
import shutil
import subprocess
import time


logging.basicConfig()
log = logging.getLogger(__name__)
log.setLevel(logging.INFO)


def sh(cmd, cwd=None, ignore_errors=False, capture=False):
    cwd = cwd or os.curdir
    cwd = os.path.abspath(cwd)
    popen_args = dict(args=cmd, shell=True, cwd=cwd)
    if capture:
        popen_args.update(dict(
            stdout=subprocess.PIPE, stderr=subprocess.PIPE))
    try:
        log.info("Running: %s", cmd)
        proc = subprocess.Popen(**popen_args)
        proc.wait()
        if capture:
            return (proc.stdout.read(), proc.stderr.read())
    except subprocess.CalledProcessError as exc:
        if not ignore_errors:
            raise
        log.error("Command failed with exit status %s: %s",
                  exc.returncode, cmd)
        if capture:
            return (exc.output, None)


def setup(env):
    # If WORKSPACE is undefined, set it to $TOXINIDIR
    if not env.get('WORKSPACE'):
        env['WORKSPACE'] = env['TOXINIDIR']

    # Write down a couple environment variables, for use in teardown
    tox_vars = os.path.join(env['WORKSPACE'], '.tox_vars')
    if os.path.exists(tox_vars):
        os.remove(tox_vars)

    tox_vars_templ = """
    export WORKSPACE={WORKSPACE}
    export CEPH_ANSIBLE_SCENARIO_PATH={CEPH_ANSIBLE_SCENARIO_PATH}
    """
    with file(tox_vars, 'w') as f:
        f.write(tox_vars_templ.format(**env))

    # Check distro and install deps
    try:
        sh('which apt-get')
        packages = ['docker.io', 'xfsprogs']
        for package in packages:
            sh('sudo apt-get install --force-yes %s' % package)
    except subprocess.CalledProcessError:
        packages = ['docker', 'xfsprogs']
        for package in packages:
            sh('sudo yum install -y %s' % package)
        # daemon doesn't start automatically after being installed
        sh('systemctl status docker || sudo systemctl restart docker')
        whoami = pwd.getpwuid(os.getuid()).pw_name
        # Allow running `docker` without sudo
        sh('sudo chgrp %s /var/run/docker.sock' % whoami)

    sh('git clone -b %s' % env['CEPH_ANSIBLE_BRANCH'] +
       '--single-branch https://github.com/ceph/ceph-ansible.git ceph-ansible')
    sh('pip install -r %s/ceph-ansible/tests/requirements.txt'
       % env['TOXINIDIR'])

    # pull requests tests should never have these directories here, but
    # branches do, so for the build scripts to work correctly, these neeed to
    # be removed
    # XXX It requires sudo because these will appear with `root` ownership
    for subdir in ['daemon', 'demo', 'base']:
        shutil.rmtree(os.path.join(env['WORKSPACE'], subdir),
                      ignore_errors=True)

    sh('bash "%s"/travis-builds/purge_cluster.sh' % env['WORKSPACE'])

    # XXX purge_cluster only stops containers, it doesn't really remove them so
    # try to remove them for real
    containers_to_remove = [item.strip() for item in
                            sh('docker ps -a -q', capture=True)[0].split()]
    for container in containers_to_remove:
        sh('docker rm -f %s' % container, ignore_errors=True)

    for subdir in ['daemon', 'demo', 'base']:
        os.mkdir(os.path.join(env['WORKSPACE'], subdir))
        # starting with kraken, the base image does not exist
        cmd = 'cp -Lrv ceph-releases/{0}/{1}/{2}/* {2}'.format(
            env['CEPH_STABLE_RELEASE'], env['IMAGE_DISTRO'], subdir)
        sh(cmd, ignore_errors=(subdir != 'daemon'))

    sh('bash "%s"/travis-builds/build_imgs.sh' % env['WORKSPACE'])

    # start a local docker registry
    sh('docker run -d -p 5000:5000 --restart=always --name registry registry:2')  # noqa
    # add the image we just built to the registry
    docker_img = 'localhost:5000/ceph/daemon:%s-latest' % \
        env['CEPH_STABLE_RELEASE']

    sh('docker tag ceph/daemon %s' % docker_img)
    # this avoids a race condition between the tagging and the push
    # which causes this to sometimes fail when run by jenkins
    time.sleep(1)
    sh('docker --debug push %s' % docker_img)


def test(env):
    # TODO: get the output image from build_imgs.sh to pass onto ceph-ansible

    # run vagrant and ceph-ansible tests
    cwd = env['CEPH_ANSIBLE_SCENARIO_PATH']
    sh('vagrant up --no-provision --provider=%s' % env['VAGRANT_PROVIDER'],
       cwd=cwd)

    sh('bash %s/ceph-ansible/tests/scripts/generate_ssh_config.sh %s' %
       (env['TOXINIDIR'], env['CEPH_ANSIBLE_SCENARIO_PATH']), cwd=cwd)

    env['ANSIBLE_SSH_ARGS'] = "-F %s/vagrant_ssh_config" % env['CEPH_ANSIBLE_SCENARIO_PATH']

    # runs a playbook to configure nodes for testing
    hosts_file = "%s/hosts" % env['CEPH_ANSIBLE_SCENARIO_PATH']
    ansible_templ = "ansible-playbook -vv -i {hosts} {therest}"
    ansible_playbook_args = [
        "{TOXINIDIR}/tests/setup.yml",
        "{TOXINIDIR}/ceph-ansible/site-docker.yml.sample --extra-vars='ceph_stable_release={CEPH_STABLE_RELEASE} ceph_docker_image_tag={CEPH_STABLE_RELEASE}-latest ceph_docker_registry={REGISTRY_ADDRESS} fetch_directory={CEPH_ANSIBLE_SCENARIO_PATH}/fetch'",
        "{TOXINIDIR}/ceph-ansible/tests/functional/setup.yml",
    ]
    for pb_args in ansible_playbook_args:
        pb_args = pb_args.format(**env)
        sh(ansible_templ.format(hosts=hosts_file, therest=pb_args), cwd=cwd)

    sh("testinfra -n 4 --sudo -v --connection=ansible --ansible-inventory={CEPH_ANSIBLE_SCENARIO_PATH}/hosts {TOXINIDIR}/ceph-ansible/tests/functional/tests".format(**env),
       cwd=cwd)


def teardown(env):
    sh("{TOXINIDIR}/tests/teardown.sh".format(**env),
        cwd=env['CEPH_ANSIBLE_SCENARIO_PATH'])


def main():
    env = os.environ
    setup(env)
    try:
        test(env)
    except Exception:
        raise
    finally:
        teardown(env)

if __name__ == '__main__':
    main()
