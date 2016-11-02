

class TestAllContainers(object):

    def test_ceph_fsid_exists(self, mon_containers, client):
        result = client.run(mon_containers, 'grep fsid /etc/ceph/ceph.conf').split()
        assert len(result) == 3
        assert result[-1] != '='
