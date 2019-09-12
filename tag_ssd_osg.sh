#!/bin/bash

# This script takes command line params in the form osd.1 osd.2
# and removes any device-class tags from them, and retags them
# with the ssd class

ceph osd crush rm-device-class $@
ceph osd crush set-device-class ssd $@
