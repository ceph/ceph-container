

class TestAllContainers(object):

    def test_ceph_fsid_exists(self, mon_containers, client):
        result = client.run(mon_containers, 'grep fsid /etc/ceph/ceph.conf').split()
        assert len(result) == 3

    def test_initial_members_is_defined(self, mon_containers, client):
        result = client.run(mon_containers, 'grep "mon initial members" /etc/ceph/ceph.conf').split()
        host_id = mon_containers['Id'][:12]
        assert result[-1] == host_id
