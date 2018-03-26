def merge_dicts(base, overrides):
    """
    Merge the base dict and the overrides dict. Values in the overrides dict overwrite values in
    the base dict. The override dict may even replace a dict with a non-dict or vise versa.
    """
    if not isinstance(base, dict) or not isinstance(overrides, dict):
        return overrides
    merged_dict = base.copy()
    for override_key, key_overrides in overrides.items():
        base_value = base.setdefault(override_key, None)
        merged_dict[override_key] = merge_dicts(base_value, key_overrides)
    return merged_dict


def _dicts_equal(d1, d2):
    # Use a sorted, serialized json dump to test for perfect dict equality
    import json
    d1_dump = json.dumps(d1, sort_keys=True)
    d2_dump = json.dumps(d2, sort_keys=True)
    return d1_dump == d2_dump


def _test_merge_dicts():
    # Add key:value pair to dict
    a = {'template': {'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    b = {'template': {'other': 'thing'}}
    m = {'template': {'other': 'thing',
                      'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    assert _dicts_equal(m, merge_dicts(a, b))

    # Override value of existing key
    a = {'template': {'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    b = {'template': {'packages': {'ceph': {'rgw': 'prgw-ceph'}}}}
    m = {'template': {'packages': {'ceph': {'rgw': 'prgw-ceph', 'list': ['p1', 'p2', 'p3']}}}}
    assert _dicts_equal(m, merge_dicts(a, b))

    # Replace existing dict value with non-dict value
    a = {'template': {'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    b = {'template': {'packages': {'ceph': None}}}
    m = {'template': {'packages': {'ceph': None}}}
    assert _dicts_equal(m, merge_dicts(a, b))

    # Replace existing non-dict value with dict value
    a = {'template': {'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    b = {'template': {'packages': {'ceph': {'rgw': {'list': ['prgw']}}}}}
    m = {'template': {'packages': {'ceph': {'list': ['p1', 'p2', 'p3'],
                                            'rgw': {'list': ['prgw']}}}}}
    assert _dicts_equal(m, merge_dicts(a, b))

    # Override empty
    a = {}
    b = {'template': {'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    m = {'template': {'packages': {'ceph': {'rgw': 'prgw', 'list': ['p1', 'p2', 'p3']}}}}
    assert _dicts_equal(m, merge_dicts(a, b))
