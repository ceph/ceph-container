#!/bin/bash

usage ()
{
    echo "$0: <image_tag> <extra_args>"
}

if [[ $# -lt 1 ]]; then
    echo "Error: must specify at least 1 argument"
    usage
    exit 1
fi

COMPOSE_ID=$(curl -s http://download.eng.bos.redhat.com/devel/candidate-trees/latest-Ceph-2-RHEL-7/COMPOSE_ID)

docker build --label=COMPOSE_ID=${COMPOSE_ID} -t ${1} ${@:2} .
