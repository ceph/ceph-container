import json
import os
import pprint
import time

import docker
from docker.errors import DockerException
import pytest


def pytest_runtest_logreport(report):
    if report.failed:
        try:
            client = docker.Client('unix://var/run/docker.sock', version="auto")
        except DockerException as e:
            raise pytest.UsageError("Could not connect to a running docker socket: %s" % str(e))

        test_containers = client.containers(
            all=True,
            filters={"label": "ceph/daemon"})
        for container in test_containers:
            log_lines = [
                ("docker inspect {!r}:".format(container['Id'])),
                (pprint.pformat(client.inspect_container(container['Id']))),
                ("docker logs {!r}:".format(container['Id'])),
                (client.logs(container['Id'])),
            ]
            report.longrepr.addsection('docker logs', os.linesep.join(log_lines))


def pull_image(image, client):
    """
    Pull the specified image using docker-py

    This function will parse the result from docker-py and raise an exception
    if there is an error.
    """
    # FIXME: this makes it really slow when re-running tests (about x5 slower).
    # This function should check if it has already pulled in the last 10
    # minutes, along with a way to override that (maybe with a flag?)
    response = client.pull(image)
    lines = [line for line in response.splitlines() if line]

    # The last line of the response contains the overall result of the pull
    # operation.
    pull_result = json.loads(lines[-1])
    if "error" in pull_result:
        raise Exception("Could not pull {}: {}".format(
            image, pull_result["error"]))


def generate_ips(start_ip, end_ip=None, offset=None):
    ip_range = []

    start = list(map(int, start_ip.split(".")))
    if offset:
        end = start[-1] + offset
        if end > 255:
            end = 255
        start = start[:-1] + [end]
    else:
        ip_range.append(start_ip)
    if not end_ip:
        end = start[:-1] + [255]
    else:
        end = list(map(int, end_ip.split(".")))
    temp = start

    while temp != end:
        start[3] += 1
        for i in (3, 2, 1):
            if temp[i] == 256:
                temp[i] = 0
                temp[i - 1] += 1
        ip_range.append(".".join(map(str, temp)))

    return ip_range


def teardown_container(client, container, container_network):
    client.remove_container(
        container=container['Id'],
        force=True
    )
    client.remove_network(container_network['Id'])


def start_container(client, container, container_network):
    """
    Start a container, wait for (successful) completion of entrypoint
    and raise an exception with container logs otherwise
    """
    try:
        client.start(container=container["Id"])
    except Exception:
        teardown_container(client, container, container_network)
        raise
    else:
        start = time.time()
        while time.time() - start < 0.5:
            if 'SUCCESS\n' in client.logs(container):
                return container

        if client.inspect_container(container)['State']['ExitCode'] > 0:
            print("[ERROR][setup] failed to setup container")
            for line in client.logs(container, stream=True):
                print("[ERROR][setup] {}".format(line.strip('\n')))
            raise RuntimeError()

        # if it has been longer than 0.5s and the container didn't get
        # a SUCCESS marker out and the `ExitCode` was 0 we can only assume this
        # is good to be used
        return container


def remove_container(client, container_name):
    # remove any existing test container
    for test_container in client.containers(all=True):
        for name in test_container['Names']:
            if container_name in name:
                client.remove_container(container=test_container['Id'], force=True)


def remove_container_network(client, container_network_name):
    # now remove any network associated with the containers
    for network in client.networks():
        if network['Name'] == container_network_name:
            client.remove_network(network['Id'])


def create_mon_container(client, container_tag):
    pull_image(container_tag, client)
    # These subnets and gateways are made up. It is *really* hard to come up
    # with a sane gateway/subnet/IP to programmatically set it for the
    # container(s)
    subnet = '172.172.172.0/16'

    # XXX This only generates a single IP, it is useful as-is because when this
    # setup wants to create multiple containers it can easily get a range of
    # IP's for the given subnet
    container_ip = generate_ips('172.172.172.1', offset=1)[-1]

    ipam_pool = docker.utils.create_ipam_pool(
        subnet='172.172.172.0/16',
        gateway='172.172.172.1'
    )

    ipam_config = docker.utils.create_ipam_config(
        pool_configs=[ipam_pool]
    )

    # create the network for the monitor, using the bridge driver
    container_network = client.create_network(
        "pytest_monitor",
        driver="bridge",
        internal=True,
        ipam=ipam_config
    )

    # now map it as part of the networking configuration
    networking_config = client.create_networking_config(
        {
            'pytest_monitor': client.create_endpoint_config(ipv4_address=container_ip)
        }
    )

    # "create" the container, which really doesn't create an actual image, it
    # basically constructs the object needed to start one. This is a 2-step
    # process (equivalent to 'docker run'). It also uses the
    # `networking_config` and `container_network` created above. These are
    # needed because the requirement for the Ceph containers is to know the IP
    # and the subnet(s) beforehand.
    container = client.create_container(
        image=container_tag,
        name='pytest_ceph_mon',
        environment={'CEPH_DAEMON': 'MON', 'MON_IP': container_ip, 'CEPH_PUBLIC_NETWORK': subnet},
        detach=True,
        networking_config=networking_config,
        command='ceph/daemon mon'
    )

    return container, container_network


def run(client):
    def run_command(container_id, command):
        created_command = client.exec_create(container_id, cmd=command)
        result = client.exec_start(created_command)
        exit_code = client.exec_inspect(created_command)['ExitCode']
        if exit_code != 0:
            msg = 'Non-zero exit code (%d) for command: %s' % (exit_code, command)
            raise(AssertionError(result), msg)
        return result
    return run_command


@pytest.fixture(scope='session')
def client():
    try:
        c = docker.Client('unix://var/run/docker.sock', version="auto")
        c.run = run(c)
        return c
    except DockerException as e:
        raise pytest.UsageError("Could not connect to a running docker socket: %s" % str(e))


container_tags = [
    'ceph/daemon:latest-mimic',
    'ceph/daemon:latest-luminous',
]

current_version_tag = [t for t in container_tags if 'mimic' in t]
previous_version_tag = [t for t in container_tags if 'luminous' in t]


@pytest.fixture(scope='class', params=current_version_tag)
def current_version_container(client, request):
    # XXX these are using 'mon' names, we need to cleanup when
    # adding tests for OSDs
    pull_image(request.param, client)
    remove_container(client, 'pytest_ceph_mon')
    remove_container_network(client, 'pytest_monitor')
    container, container_network = create_mon_container(client, request.param)
    start_container(client, container, container_network)

    yield container

    teardown_container(client, container, container_network)


@pytest.fixture(scope='class', params=previous_version_tag)
def previous_version_container(client, request):
    # XXX these are using 'mon' names, we need to cleanup when
    # adding tests for OSDs
    pull_image(request.param, client)
    remove_container(client, 'pytest_ceph_mon')
    remove_container_network(client, 'pytest_monitor')
    container, container_network = create_mon_container(client, request.param)
    start_container(client, container, container_network)

    yield container

    teardown_container(client, container, container_network)


@pytest.fixture(scope='class', params=container_tags)
def mon_containers(client, request):
    # XXX these are using 'mon' names, we need to cleanup when
    # adding tests for OSDs
    pull_image(request.param, client)
    remove_container(client, 'pytest_ceph_mon')
    remove_container_network(client, 'pytest_monitor')
    container, container_network = create_mon_container(client, request.param)
    start_container(client, container, container_network)

    yield container

    teardown_container(client, container, container_network)
