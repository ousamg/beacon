#!/usr/bin/env python
from __future__ import print_function

import argparse
import datetime
import json
import digitalocean
import sys
import time


DEF_CONFIG = {
    "token": None, # always load from file
    "region": None,
    "name": "beacon",
    "image": "docker-16-04", # pre-made docker image
    "size_slug": "s-1vcpu-1gb",
    "monitoring": True,
    "tags": []
}
MAX_ATTEMPTS = 5


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', required=True, metavar="config.json",
                        help='Config with DigitalOcean token, region and any additional info')
    parser.add_argument('-t', '--tags', nargs='+', metavar="TAG_NAME", help='Tags for the droplet')
    parser.add_argument('--verbose', action='store_true', help="be extra chatty")
    parser.add_argument('--debug', action='store_true', help="run in debug mode")
    args = parser.parse_args()

    if args.debug:
        setattr(args, 'verbose', True)

    droplet_config = DEF_CONFIG.copy()
    with open(args.config) as cfg_file:
        json_config = json.load(cfg_file)
        for k, v in json_config.items():
            if k in droplet_config and droplet_config[k] is not None:
                if not isinstance(v, type(droplet_config[k])):
                    raise(TypeError("Expected {} for {}, but got {}".format(type(droplet_config[k]), k, type(v))))
            droplet_config[k] = v
    if args.tags:
        droplet_config["tags"] += args.tags

    if args.debug:
        debug_log("Using config: {}".format(json.dumps(droplet_config)))

    mgr = digitalocean.Manager(token=droplet_config["token"])

    if "ssh_keys" in droplet_config:
        if args.verbose:
            info_log("Getting account SSH keys")
        ssh_keys = {k.name: k for k in mgr.get_all_sshkeys()}
        droplet_config["ssh_keys"] = [ssh_keys[k] for k in droplet_config["ssh_keys"]]
        if args.verbose:
            info_log("Added {} keys to droplet".format(len(droplet_config["ssh_keys"])))

    if args.debug:
        debug_log("Using config: {}".format(json.dumps(droplet_config, cls=KeyEncoder)))

    d = digitalocean.Droplet(**droplet_config)
    d.create()
    acts = d.get_actions()
    act_attempts = 0
    while act_attempts < MAX_ATTEMPTS:
        if args.debug:
            debug_log("Getting actions attempt #{}".format(act_attempts))
        if len(acts) > 0:
            creation = [x for x in acts if x.type == "create"]
            if len(creation) > 0:
                if args.debug:
                    debug_log("Got it in {}".format(act_attempts))
                creation = creation[0]
                break
        if args.debug:
            debug_log("Sleeping for {} after unsuccesful attempt to get actions".format(2**act_attempts))
        time.sleep(2**act_attempts)
        acts = d.get_actions()
        act_attempts += 1

    if creation == []:
        err_log("Failed to find creation action on droplet after {} attempts, something went wrong".format(act_attempts))
        sys.exit(1)
    elif args.verbose:
        info_log("Waiting for droplet to finish provisioning")

    # sleeps until creation.status == "complete"
    creation.wait()
    if args.debug:
        debug_log("Creation successful, reloading droplet info")
    d.load()

    if args.verbose:
        info_log("Created new droplet successfully")
        info_log("Droplet IP: {}".format(d.ip_address))
    else:
        print(d.ip_address)


def err_log(msg):
    _log(msg, "ERROR")


def debug_log(msg):
    _log(msg, "DEBUG")


def info_log(msg):
    _log(msg, "INFO")


def _log(msg, level):
    sys.stderr.write("{}\t{}\t{}\n".format(now(), level, msg))


def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


class KeyEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, digitalocean.SSHKey):
            return str(o)
        else:
            return o.__dict__


###


if __name__ == '__main__':
    main()
