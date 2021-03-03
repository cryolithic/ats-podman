#! /usr/bin/python3

import jinja2
import json
import os.path
import socket
import struct
import subprocess
import sys


PRJ_DIR = os.path.join(os.path.dirname(__file__), '..')
TPL = os.path.join(PRJ_DIR, 'assets/network-static.js.j2')


def podman_get_network_config(container_name, network_name):
    output = subprocess.getoutput(f'podman inspect --format json {container_name}')
    j = json.loads(output)
    return j[0]['NetworkSettings']['Networks'][network_name]


def get_netmask_from_prefix_len(prefix_len):
    mask = (1 << 32) - (1 << 32 >> prefix_len)
    return socket.inet_ntoa(struct.pack(">L", mask))


if __name__ == '__main__':
    container_name, network_name = sys.argv[1:]

    with open(TPL) as f:
        tpl = jinja2.Template(f.read())

    vars = podman_get_network_config(container_name, network_name)
    vars['Netmask'] = get_netmask_from_prefix_len(vars['IPPrefixLen'])

    print(tpl.render(**vars))
