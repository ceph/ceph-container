#!/usr/bin/python
import re
import os
import subprocess
import json
MON_REGEX = r"^\d: ([0-9\.]*):\d+/\d* mon.([^ ]*)$"


#kubctl_command = 'kubectl get pods --namespace=${CLUSTER} -l daemon=mon -o template --template="{ {{range .items}} \\"{{.metadata.name}}\\": \\"{{.status.podIP}}\\" ,   {{end}} }"'
kubectl_command = 'kubectl get pods --namespace=${CLUSTER} -l daemon=mon -o template --template="{ {{range  \$i, \$v  := .items}} {{ if \$i}} , {{ end }} \\"{{\$v.metadata.name}}\\": \\"{{\$v.status.podIP}}\\" {{end}} }"'
monmap_command = "ceph --cluster=${CLUSTER} mon getmap > /tmp/monmap && monmaptool -f /tmp/monmap --print"



def extract_mons_from_monmap():
    monmap = subprocess.check_output(monmap_command, shell=True)
    mons = {}
    for line in monmap.split("\n"):
        m = re.match(MON_REGEX, line)
        if m is not None:
            mons[m.group(2)] = m.group(1)
    return mons

def extract_mons_from_kubeapi():
    kubemap = subprocess.check_output(kubectl_command, shell=True)
    return json.loads(kubemap)

current_mons = extract_mons_from_monmap()
expected_mons = extract_mons_from_kubeapi()

print "current mons:", current_mons
print "expected mons:", expected_mons

for mon in current_mons:
    removed_mon = False
    if not mon in expected_mons:
        print "removing zombie mon ", mon
        subprocess.call(["ceph", "--cluster", os.environ["CLUSTER"], "mon", "remove", mon])
        removed_mon = True
    elif current_mons[mon] != expected_mons[mon]: # check if for some reason the ip of the mon changed
        print "ip change dedected for pod ", mon
        subprocess.call(["kubectl", "--namespace", os.environ["CLUSTER"], "delete", "pod", mon])
        removed_mon = True
        print "deleted mon %s via the kubernetes api" % mon


if not removed_mon:
    print "no zombie mons found ..."
