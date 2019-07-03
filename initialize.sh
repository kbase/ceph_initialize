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
