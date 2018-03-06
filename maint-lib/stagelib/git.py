# Copyright (c) 2017 SUSE LLC

import logging
import re
import subprocess


# Run a command, and return the result in string format, stripped. Return None if command fails.
def _run_cmd(cmd_array):
    try:
        return subprocess.check_output(cmd_array).decode("utf-8").strip()
    except subprocess.CalledProcessError as c:
        logging.warning('Command {} return error code [{}]:'.format(c.cmd, c.returncode))
        return None


def get_repo():
    """Returns the current git repo; or 'Unknown repo' if there is an error."""
    repo = _run_cmd(['git', 'ls-remote', '--get-url', 'origin'])
    return 'Unknown repo' if repo is None else repo


def get_branch():
    """Returns the current git branch; or 'Unknown branch' if there is an error."""
    branch = _run_cmd(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
    return 'Unknown branch' if branch is None else branch


def get_hash():
    """Returns the current git commit hash; or 'Unknown commit hash' if there is an error."""
    commithash = _run_cmd(['git', 'rev-parse', '--verify', 'HEAD'])
    return 'Unknown commit hash' if commithash is None else commithash


def file_is_dirty(file_path):
    """If a file is new, modified, or deleted in git's tracking return True. False otherwise."""
    file_status_msg = _run_cmd(['git', 'status', '--untracked-files=all', str(file_path)])
    # git outputs filename on a line prefixed by whitespace if the file is new/modified/deleted
    if re.match(r'^\s*' + file_path + '$', file_status_msg):
        return True
    return False
