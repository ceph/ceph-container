#!/usr/bin/env python3

import os
import logging
import shutil
import sys
import time


from stagelib.envglobals import *  # noqa: F403
from stagelib.filecopytools import list_files, mkdir_if_dne, copy_files, recursive_copy_dir
from stagelib.replace import do_variable_replace
from stagelib.blacklist import get_blacklist

if sys.version_info[0] < 3:
    print('This must be run with Python 3+')
    sys.exit(1)

curtime = time.time()
if os.path.isfile('stage.log') and \
        (time.time() - os.path.getmtime('stage.log') > 86400):
    os.remove('stage.log')  # poor man's log rotator: delete log if it's old
logging.basicConfig(filename='stage.log', level=logging.DEBUG,
                    format='%(levelname)5s:  %(message)s')
logger = logging.getLogger(__name__)


def main():
    logger.info('\n\n\n')  # Make it easier to determine where new runs start
    logger.info('Start time: {}'.format(time.ctime()))

    print('')
    printGlobal(CEPH_VERSION)  # noqa: F405
    printGlobal(BASEOS_NAME)  # noqa: F405
    printGlobal(BASEOS_TAG)  # noqa: F405
    printGlobal(BASEOS_REG)  # noqa: F405
    printGlobal(ARCH)  # noqa: F405
    printGlobal(IMAGES_TO_BUILD)  # noqa: F405
    printGlobal(STAGING_DIR)  # noqa: F405
    printGlobal(BASE_IMAGE)  # noqa: F405
    print('')

    # Search from least specfic to most specific
    path_search_order = [
        "core",
        "all_ceph_releases",
        "all_ceph_releases/{}".format(BASEOS_NAME),  # noqa: F405
        "all_ceph_releases/{}/{}".format(BASEOS_NAME, BASEOS_TAG),  # noqa: F405
        "{}".format(CEPH_VERSION),  # noqa: F405
        "{}/{}".format(CEPH_VERSION, BASEOS_NAME),  # noqa: F405
        "{}/{}/{}".format(CEPH_VERSION, BASEOS_NAME, BASEOS_TAG),  # noqa: F405
    ]

    # Start with empty staging dir so there are no previous artifacts
    if os.path.isdir(STAGING_DIR):  # noqa: F405
        shutil.rmtree(STAGING_DIR)  # noqa: F405
    os.mkdir(STAGING_DIR, mode=0o755)  # noqa: F405

    blacklist = get_blacklist('flavor_blacklist.txt')
    logger.debug('Blacklist: {}'.format(blacklist))

    for image in IMAGES_TO_BUILD:  # noqa: F405
        for src_path in path_search_order:
            if not os.path.isdir(src_path):
                continue
            src_files = list_files(src_path)
            # e.g., IMAGES_TO_BUILD = ['daemon-base', 'daemon']
            staging_path = os.path.join(STAGING_DIR, image)  # noqa: F405
            mkdir_if_dne(staging_path, mode=0o755)
            logger.info('Copy {} files to {}'.format(src_path, staging_path))
            copy_files(src_files, src_path, staging_path, blacklist)
            logger.info('Copy {} files to {}'.format(
                os.path.join(src_path, image), staging_path))
            recursive_copy_dir(src_path=os.path.join(src_path, image), dst_path=staging_path,
                               blacklist=blacklist)
        do_variable_replace(replace_root_dir=os.path.join(STAGING_DIR, image))  # noqa: F405


if __name__ == "__main__":
    main()
