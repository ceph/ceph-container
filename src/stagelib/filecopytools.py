import logging
import os
import shutil


# List only files in dir
def list_files(path):
    """ List all files in the path non-recursively. Do not list dirs."""
    return [f for f in os.listdir(path)
            if os.path.isfile(os.path.join(path, f))]


def mkdir_if_dne(path, mode=0o755):
    """Make a directory if it does not exist"""
    if not os.path.isdir(path):
        os.mkdir(path, mode)


def copy_files(filenames, src_path, dst_path, blacklist):
    """
    Copy a list of filenames from src to dst. Will overwrite existing files.
    If any files are in the blacklist, they will not be copied.
    If the src directory is in the blacklist, the dest path will not be created, and the files will
      not be copied or processed.
    """
    # Adding a trailing "/" if needed to improve output coherency
    dst_path = os.path.join(dst_path, '')
    logging.debug('      {:<80}    -> {}'.format(src_path+'/', dst_path))
    if os.path.join(src_path, '') in blacklist:
        logging.info('\t{:<80}     [DIR BLACKLISTED]'.format(src_path))
        return
    mkdir_if_dne(dst_path)
    for f in filenames:
        file_path = os.path.join(src_path, f)
        if file_path in blacklist:
            logging.info('\t{:<80}     [FILE BLACKLISTED]'.format(file_path))
            continue
        logging.info('\t{:<80}  -> {}'.format(file_path, dst_path))
        shutil.copy2(file_path, dst_path)


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
            logging.info('\t{:<80}     [DIR BLACKLISTED]'.format(dirname))
            subdirs[:] = []
            continue
        dst_path_offset = dirname[len(src_path)+1:]
        copy_files(filenames=files, src_path=dirname,
                   dst_path=os.path.join(dst_path, dst_path_offset), blacklist=blacklist)
