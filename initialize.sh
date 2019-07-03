#!/bin/bash -x

# Script that performs basic initialization of a node to join a ceph cluster as an OSD
# Based on combination of
# https://geek-cookbook.funkypenguin.co.nz/ha-docker-swarm/shared-storage-ceph/
# and the notes from this github trouble ticket
# https://github.com/ceph/ceph-container/issues/1395
#
# The partition initialization/preparation is only necessary until the docker image
# entrypoint scripts catch up to the latest ceph changes

# NOTE: You need to have brought up the ceph monitor once, so that the initial
# configuration has been created, and then copied the /etc/ceph directory from
# that container to the location specified in CEPH_ETC below.
#
# The container should have a bind mount for /etc/ceph that points to a persistent
# location that will be re-mounted as /etc/ceph for the remaining Mon, Mgr, MDS, RGW,
# and OSD containers.
#
# This script expects 2 environment variables to be set:
# CEPH_ETC - this is the path to a directory that contains the initial
#            cluster config in /etc/ceph created by the first ceph monitor
#            The contents of CEPH_ETC will be copied to the /etc/ceph directory
#            within the running container.
# OSD_DEV - this is the block device that should be wrapped up into a logical
#           volume and then prepared using ceph-volume lvm prepare for use with
#           with the ceph osd
#
# 
# sychan@lbl.gov
# 7/3/2019

if [ -z "$CEPH_ETC" ]; then
    echo "The environment variable CEPH_ETC has not been set"
    exit 1
fi
if [ ! -d "$CEPH_ETC" ]; then
    echo "$CEPH_ETC must be a directory"
    exit 1
fi

if [ -z "$OSD_DEV" ]; then
    echo "The environment variable OSD_DEV has not been set"
    exit 1
fi

if [ ! -b "$OSD_DEV" ]; then
    echo "$OSD_DEV must be a block device"
    exit 1
fi

if [ ! -d "/etc/ceph" ]; then
    echo "The directory /etc/ceph must exist and should be a persistent volume mount"
fi

echo "Copying $CEPH_ETC to /etc/ceph..."
cp -r $CEPH_ETC/* /etc/ceph/

echo "Running ceph-volume to prepare $OSD_DEV"
ceph-volume lvm prepare --bluestore --data $OSD_DEV

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to prepare $OSD_DEV as a bluestore device. Exitting"
    exit 1
fi

ceph-volume lvm list --format json
