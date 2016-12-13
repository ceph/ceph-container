

class TestAll(object):

    def test_ceph_version(self, mon_containers, client):
        command = client.exec_create(mon_containers, cmd='ceph --version')
        result = client.exec_start(command)
        assert 'ceph version' in result

    def test_etc_ceph_conf_exists(self, mon_containers, client):
        command = client.exec_create(mon_containers, cmd='stat /etc/ceph/ceph.conf')
        result = client.exec_start(command)
        if client.exec_inspect(command)['ExitCode'] != 0:
            raise AssertionError(result)

    def test_socket_dir_exists(self, mon_containers, client):
        command = client.exec_create(mon_containers, cmd='stat /var/run/ceph')
        result = client.exec_start(command)
        if client.exec_inspect(command)['ExitCode'] != 0:
            raise AssertionError(result)

    def test_ceph_health(self, mon_containers, client):
        command = client.exec_create(mon_containers, cmd='ceph health')
        result = client.exec_start(command)
        assert result.startswith('HEALTH_ERR ')

    def test_keyring_exists(self, mon_containers, client):
        command = client.exec_create(mon_containers, cmd='stat /etc/ceph/ceph.mon.keyring')
        result = client.exec_start(command)
        if client.exec_inspect(command)['ExitCode'] != 0:
            raise AssertionError(result)

    def test_monmap_exists(self, mon_containers, client):
        command = client.exec_create(mon_containers, cmd='stat /etc/ceph/monmap-ceph')
        result = client.exec_start(command)
        if client.exec_inspect(command)['ExitCode'] != 0:
            raise AssertionError(result)


class TestJewel(object):

    def test_socket_dir_is_owned_by_ceph(self, jewel_containers, client):
        command = client.exec_create(jewel_containers, cmd='ls -ld /var/run/ceph')
        result = client.exec_start(command)
        if client.exec_inspect(command)['ExitCode'] != 0:
            raise AssertionError(result)
        assert result.split()[2] == 'ceph'
