# Copyright (c) 2017 SUSE LLC

import logging
import os
import shutil
import sys

COPY_LOGTEXT = '        {:<80}  -> {}'
PARENTHETICAL_LOGTEXT = '        {:<80}     {}'


def IOOSErrorGracefulFail(io_os_error, message):
    """
    Given an IOError or OSError exception, print the message to stdout, and then print relevant
    stats about the exception to stdout before exiting with error code 1.
    """
    o = io_os_error
    sys.stderr.write('{}\n'.format(message))
    # errno and strerror are common to IOError and OSError
    sys.stderr.write('Error [{}]: {}\n'.format(o.errno, o.strerror))
    sys.exit(1)


def save_text_to_file(text, file_path):
    """Save text to a file at the file path. Will overwrite an existing file at the same path."""
    try:
        with open(file_path, 'w') as f:
            f.write(text)
    except (OSError, IOError) as o:
        IOOSErrorGracefulFail(o, "Could not write text to file: {}".format(file_path))


# List only files in dir
def list_files(path):
    """ List all files in the path non-recursively. Do not list dirs."""
    return [f for f in os.listdir(path)
            if os.path.isfile(os.path.join(path, f))]


def mkdir_if_dne(path, mode=0o755):
    """Make a directory if it does not exist"""
    if not os.path.isdir(path):
        try:
            os.mkdir(path, mode)
        except (OSError, IOError) as o:
            IOOSErrorGracefulFail(o, "Could not create directory: {}".format(path))


# Copy file from src to dst
def _copy_file(file_path, dst_path):
    try:
        shutil.copy2(file_path, dst_path)
    except (OSError, IOError) as o:
        IOOSErrorGracefulFail(o, "Could not copy file {} to {}".format(file_path, dst_path))


def copy_files(filenames, src_path, dst_path, blacklist):
    """
    Copy a list of filenames from src to dst. Will overwrite existing files.
    If any files are in the blacklist, they will not be copied.
    If the src directory is in the blacklist, the dest path will not be created, and the files will
      not be copied or processed.
    """
    # Adding a trailing "/" if needed to improve output coherency
    dst_path = os.path.join(dst_path, '')
    if os.path.join(src_path, '') in blacklist:
        logging.info(PARENTHETICAL_LOGTEXT.format(src_path, '[DIR BLACKLISTED]'))
        return
    mkdir_if_dne(dst_path)
    for f in filenames:
        file_path = os.path.join(src_path, f)
        if file_path in blacklist:
            logging.info(PARENTHETICAL_LOGTEXT.format(file_path, '[FILE BLACKLISTED]'))
            continue
        logging.info(COPY_LOGTEXT.format(file_path, dst_path))
        _copy_file(file_path, dst_path)


def recursive_copy_dir(src_path, dst_path, blacklist=[]):
    """
    Copy all files in the src directory recursively to dst. Will overwrite existing files.
    If any files encountered are in the blacklist, they will not be copied.
    If any directories encountered are in the blacklist, the corresponding dest path will not be
      created, and files/subdirs within the blacklisted dir will not be copied.
    """
    if not os.path.isdir(src_path):
        return
    for dirname, subdirs, files in os.walk(src_path, topdown=True):
        # Remove src_path (and '/' immediately following) from our dirname
        if os.path.join(dirname, '') in blacklist:
            logging.info(PARENTHETICAL_LOGTEXT.format(dirname, '[DIR BLACKLISTED]'))
            subdirs[:] = []
            continue
        dst_path_offset = dirname[len(src_path)+1:]
        copy_files(filenames=files, src_path=dirname,
                   dst_path=os.path.join(dst_path, dst_path_offset), blacklist=blacklist)
