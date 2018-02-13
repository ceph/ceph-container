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


def copy_files(filenames, src_path, dst_path):
    """Copy a list of filenames from src to dst. Will overwrite existing files."""
    for f in filenames:
        logging.info('    {:<60}  -> {}'.format(os.path.join(src_path, f), dst_path))
        shutil.copy2(os.path.join(src_path, f), dst_path)


def recursive_copy_dir(src_path, dst_path):
    """Copy all files in a directory recursively to dst. Will overwrite existing files."""
    if not os.path.isdir(src_path):
        return
    for dirname, subdirs, files in os.walk(src_path, topdown=True):
        # Remove src_path (and '/' immediately following) from our dirname
        dst_path_offset = dirname[len(src_path)+1:]
        dst_path_subdir = os.path.join(dst_path, dst_path_offset)
        mkdir_if_dne(dst_path_subdir)
        copy_files(files, dirname, dst_path_subdir)
