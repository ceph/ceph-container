# Copyright (c) 2017 SUSE LLC

import logging
import os
import stagelib.git as git
import shutil
import stagelib.git as git
import sys

COPY_LOGTEXT = '      {:<82}  -> {:1}'
PARENTHETICAL_LOGTEXT = '        {:<80}     {}'


def IOOSErrorGracefulFail(io_os_error, message):
    o = io_os_error
    sys.stderr.write('{}\n'.format(message))
    # errno and strerror are common to IOError and OSError
    sys.stderr.write('Error [{}]: {}\n'.format(o.errno, o.strerror))
    sys.exit(1)


def save_text_to_file(text, file_path):
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


def _copy_file(file_path, dst_path):
    try:
        shutil.copy2(file_path, dst_path)
    except (OSError, IOError) as o:
        IOOSErrorGracefulFail(o, "Could not copy file {} to {}".format(file_path, dst_path))


def copy_files(filenames, src_path, dst_path, blacklist=[], files_copied={}):
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
        dirty_marker = '*' if git.file_is_dirty(file_path) else ' '
        logging.info(COPY_LOGTEXT.format(dirty_marker + ' ' + file_path, dst_path))
        files_copied[os.path.join(dst_path, f)] = dirty_marker + ' ' + file_path
        _copy_file(file_path, dst_path)


def recursive_copy_dir(src_path, dst_path, blacklist=[], files_copied={}):
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
                   dst_path=os.path.join(dst_path, dst_path_offset),
                   blacklist=blacklist, files_copied=files_copied)


def save_files_copied(files_copied, save_filename, strip_prefix=' '):
    printfmt = '{:<80}  <- {}\n'
    filetext = printfmt.format('<staged file>',
                               '  <source file> (preceding* indicates file modified)')
    for staged_file, source_file in files_copied.items():
        if staged_file.startswith(strip_prefix):
            staged_file = staged_file[len(strip_prefix):]
        filetext += printfmt.format(staged_file, source_file)
    save_text_to_file(filetext, save_filename)
