#!/usr/bin/env python3
# Copyright (c) 2017 SUSE LLC

import os
import logging
import shutil
import sys
import time

from stagelib.envglobals import (printGlobal, CEPH_VERSION, OS_NAME, OS_VERSION,
                                 IMAGES_TO_BUILD, STAGING_DIR)
from stagelib.filetools import (list_files, mkdir_if_dne, copy_files, recursive_copy_dir,
                                IOOSErrorGracefulFail, save_files_copied)
import stagelib.git as git
from stagelib.replace import do_variable_replace
from stagelib.blacklist import get_blacklist


# Set default values for tunables (primarily only interesting for testing)
CORE_FILES_DIR = "src"
CEPH_RELEASES_DIR = "ceph-releases"
BLACKLIST_FILE = "flavor-blacklist.txt"
LOG_FILE = os.path.join(STAGING_DIR, "stage.log")

# Start with empty staging dir so there are no previous artifacts
try:
    if os.path.isdir(STAGING_DIR):
        shutil.rmtree(STAGING_DIR)
    os.makedirs(STAGING_DIR, mode=0o755)
except (OSError, IOError) as o:
    IOOSErrorGracefulFail(o,
                          'Could not delete and recreate staging dir: {}'.format(STAGING_DIR))

loglevel = logging.INFO
# If DEBUG env var is set to anything (including empty string) except '0', log debug text
if 'DEBUG' in os.environ and not os.environ['DEBUG'] == '0':
    loglevel = logging.DEBUG
logging.basicConfig(filename=LOG_FILE, level=loglevel,
                    format='%(levelname)5s:  %(message)s')
logger = logging.getLogger(__name__)

# Build dependency on python3 for `replace.py`. Looking to py2.7 deprecation in 2020.
if sys.version_info[0] < 3:
    print('This must be run with Python 3+')
    sys.exit(1)


def main(CORE_FILES_DIR, CEPH_RELEASES_DIR, BLACKLIST_FILE):
    logger.info('\n\n\n')  # Make it easier to determine where new runs start
    logger.info('Start time: {}'.format(time.ctime()))
    logger.info('Git repo:   {}'.format(git.get_repo()))
    logger.info('Git branch: {}'.format(git.get_branch()))
    logger.info('Git commit: {}'.format(git.get_hash()))

    print('')
    printGlobal('CEPH_VERSION')
    printGlobal('OS_NAME')
    printGlobal('OS_VERSION')
    printGlobal('BASEOS_REG')
    printGlobal('BASEOS_REPO')
    printGlobal('BASEOS_TAG')
    printGlobal('ARCH')
    printGlobal('GENERIC_ARCH')
    printGlobal('IMAGES_TO_BUILD')
    printGlobal('STAGING_DIR')
    print('')

    # Search from least specfic to most specific
    path_search_order = [
        "{}".format(CORE_FILES_DIR),
        os.path.join(CEPH_RELEASES_DIR, 'ALL'),
        os.path.join(CEPH_RELEASES_DIR, 'ALL', OS_NAME),
        os.path.join(CEPH_RELEASES_DIR, 'ALL', OS_NAME, OS_VERSION),
        os.path.join(CEPH_RELEASES_DIR, CEPH_VERSION),
        os.path.join(CEPH_RELEASES_DIR, CEPH_VERSION, OS_NAME),
        os.path.join(CEPH_RELEASES_DIR, CEPH_VERSION, OS_NAME, OS_VERSION),
    ]
    logger.debug('Path search order: {}'.format(path_search_order))

    blacklist = get_blacklist(BLACKLIST_FILE)
    logger.debug('Blacklist: {}'.format(blacklist))

    files_copied = {}
    # e.g., IMAGES_TO_BUILD = ['daemon-base', 'daemon']
    for image in IMAGES_TO_BUILD:
        logger.info('')
        logger.info('{}/'.format(image))
        logger.info('    Copying files (preceding * indicates file has been modified)')
        for src_path in path_search_order:
            if not os.path.isdir(src_path):
                continue
            src_files = list_files(src_path)
            staging_path = os.path.join(STAGING_DIR, image)
            mkdir_if_dne(staging_path, mode=0o755)
            # Copy files in each path first, then copy contents of <image> dir
            copy_files(src_files, src_path, staging_path, blacklist, files_copied)
            recursive_copy_dir(src_path=os.path.join(src_path, image), dst_path=staging_path,
                               blacklist=blacklist, files_copied=files_copied)
        # Do variable replacements on all files in <staging>/<image>
        do_variable_replace(replace_root_dir=os.path.join(STAGING_DIR, image))

    # Save a file named files-sources to the staging dir
    save_files_copied(files_copied, os.path.join(STAGING_DIR, 'files-sources'),
                      strip_prefix=os.path.join(STAGING_DIR, ''))
    copy_files(['find-src'], 'maint-lib/stagelib', STAGING_DIR)


if __name__ == "__main__":
    main(CORE_FILES_DIR, CEPH_RELEASES_DIR, BLACKLIST_FILE)
