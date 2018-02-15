# Copyright (c) 2017 SUSE LLC

import subprocess


def _run_cmd(cmd_array):
    return subprocess.check_output(cmd_array).decode("utf-8").strip()


def get_repo():
    return _run_cmd(['git', 'ls-remote', '--get-url', 'origin'])


def get_branch():
    return _run_cmd(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])


def get_hash():
    return _run_cmd(['git', 'rev-parse', '--verify', 'HEAD'])
