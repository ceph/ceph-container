

class TestAllContainers(object):

    def test_ceph_fsid_exists(self, mon_containers, client):
        result = client.run(mon_containers, 'grep fsid /etc/ceph/ceph.conf').split()
        assert len(result) == 3

    def test_initial_members_is_defined(self, mon_containers, client):
        result = client.run(mon_containers, 'grep "mon initial members" /etc/ceph/ceph.conf').split()
        host_id = mon_containers['Id'][:12]
        assert result[-1] == host_id

    def test_cluster_is_required(self, mon_containers, client):
        result = client.run(mon_containers, 'grep "auth cluster required" /etc/ceph/ceph.conf')
        assert result == 'auth cluster required = cephx\n'

    def test_service_is_required(self, mon_containers, client):
        result = client.run(mon_containers, 'grep "auth service required" /etc/ceph/ceph.conf')
        assert result == 'auth service required = cephx\n'

    def test_client_is_required(self, mon_containers, client):
        result = client.run(mon_containers, 'grep "auth client required" /etc/ceph/ceph.conf')
        assert result == 'auth client required = cephx\n'
