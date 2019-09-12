#!/bin/bash -x

# Script that performs basic initialization of a node to join a ceph cluster
# https://geek-cookbook.funkypenguin.co.nz/ha-docker-swarm/shared-storage-ceph/

# NOTE: You need to have brought up the ceph monitor once, so that the initial
# configuration has been created, and then copied the /etc/ceph directory from
# that container to the location specified in CEPH_ETC below.
#
# The container should have a bind mount for /etc/ceph that points to a persistent
# location that will be re-mounted as /etc/ceph for the remaining Mon, Mgr, MDS, RGW,
# and OSD containers.
#
# This script expects 1 environment variable to be set:
# CEPH_ETC - this is the path to a directory that contains the initial
#            cluster config in /etc/ceph created by the first ceph monitor
#            The contents of CEPH_ETC will be copied to the /etc/ceph directory
#            within the running container.
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

if [ ! -d "/etc/ceph" ]; then
    echo "The directory /etc/ceph must exist and should be a persistent volume mount"
fi

echo "Copying $CEPH_ETC to /etc/ceph..."
cp -r $CEPH_ETC/* /etc/ceph/

echo <<EOT
The persistent volume mounted at /etc/ceph should be ready for running ceph
mon, mgr, osd, mds, rgw, etc...

Note that before an OSD can join the cluster it will need to have a running
ceph monitoring service and have the initialize-osd.sh script run
to prepare credentials and initialize the block device as an OSD volume. Make
sure that a ceph mon service is available to the container before running the
initialize-osd.sh script

EOT
