#!/usr/bin/env bash
set -xe


# FUNCTIONS
function create_disk {
    local node_number
    local disk_image=${1}
    local storage_data_dir=${2}
    local loopback_disk_size=${3}

    # Create a loopback disk and format it to XFS.
    if [[ -e ${disk_image} ]]; then
        if egrep -q ${storage_data_dir} /proc/mounts; then
            sudo umount ${storage_data_dir}
            sudo rm -f ${disk_image}
        fi
    fi

    sudo mkdir -p ${storage_data_dir}

    sudo truncate -s ${loopback_disk_size} ${disk_image}

    # Make a fresh XFS filesystem. Use bigger inodes so xattr can fit in
    # a single inode. Keeping the default inode size (256) will result in multiple
    # inodes being used to store xattr. Retrieving the xattr will be slower
    # since we have to read multiple inodes. This statement is true for both
    # Swift and Ceph.
    sudo mkfs.xfs -f -i size=1024 ${disk_image}

    # Mount the disk with mount options to make it as efficient as possible
    if ! egrep -q ${storage_data_dir} /proc/mounts; then
        sudo mount -t xfs -o loop,noatime,nodiratime,nobarrier,logbufs=8  \
            ${disk_image} ${storage_data_dir}
    fi
}


# MAIN
create_disk /tmp/ceph.img /var/lib/ceph 20G
