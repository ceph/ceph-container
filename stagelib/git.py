# Copyright (c) 2017 SUSE LLC

import re
import subprocess


def _run_cmd(cmd_array):
    return subprocess.check_output(cmd_array).decode("utf-8").strip()


def get_repo():
    return _run_cmd(['git', 'ls-remote', '--get-url', 'origin'])


def get_branch():
    return _run_cmd(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])


def get_hash():
    return _run_cmd(['git', 'rev-parse', '--verify', 'HEAD'])


def file_is_dirty(file_path):
    file_status_msg = _run_cmd(['git', 'status', '--untracked-files=all', str(file_path)])
    # git outputs filename on a line prefixed by whitespace if the file is new/modified/deleted
    if re.match(r'^\s*' + file_path + '$', file_status_msg):
        return True
    return False
