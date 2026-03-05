#!/usr/bin/env python3

import os
import re

def get_password(machine, login, port):
    s = f"machine {machine} login {login} port {port} password ([^ ]*)\n"
    p = re.compile(s)
    authinfo_pass = os.popen("security find-generic-password -a authinfo -s authinfo -w").read()
    authinfo_cmd = "gpg -q -d --no-mdc-warning --no-tty --pinentry-mode=loopback --passphrase " + authinfo_pass.strip() + " ~/.authinfo.gpg"
    authinfo = os.popen(authinfo_cmd).read()
    password = p.search(authinfo).group(1)
    return password
