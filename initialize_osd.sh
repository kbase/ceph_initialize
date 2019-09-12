#!/bin/bash -x

# Script to be run *after* the initilize_cluster_creds.sh script. This script performs
# configuration specific to the OSD service. 
# Based on combination of
# https://geek-cookbook.funkypenguin.co.nz/ha-docker-swarm/shared-storage-ceph/
# and the notes from this github trouble ticket
# https://github.com/ceph/ceph-container/issues/1395
#
# The partition initialization/preparation is only necessary until the docker image
# entrypoint scripts catch up to the latest ceph changes

# NOTE: You need to have brought up the ceph monitor on this host
#
# The container should have a bind mount for /etc/ceph as well as /var/lib/ceph that
# points to a persistent locations that will be re-mounted as /etc/ceph for the
# OSD containers.
#
# This script expects 1 environment variable to be set:
# OSD_DEV - this is the block device that should be wrapped up into a logical
#           volume and then prepared using ceph-volume lvm prepare for use with
#           with the ceph osd
#
# 
# sychan@lbl.gov
# 7/3/2019

if [ -z "$OSD_DEV" ]; then
    echo "The environment variable OSD_DEV has not been set"
    exit 1
fi

if [ ! -b "$OSD_DEV" ]; then
    echo "$OSD_DEV must be a block device"
    exit 1
fi

if [ -n "$OSD_JOURNAL_DEV" ] && [ ! -b "$OSD_JOURNAL_DEV" ]; then
    echo "$OSD_JOURNAL_DEV must be a block device"
    exit 1
fi

echo "Dumping auth credentials for the OSD and RGW bootstrap..."

ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/ceph.keyring
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to dump bootstrap OSD credentials using ceph auth. Exitting"
    exit 1
fi

ceph auth get client.bootstrap-rgw -o /var/lib/ceph/bootstrap-rgw/ceph.keyring
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to dump rgw OSD credentials using ceph auth. Exitting"
    exit 1
fi

echo "Running pvcreate on $OSD_DEV to prepare for ceph volume initialization..."
pvcreate $OSD_DEV

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to run pvcreate on $OSD_DEV. Exitting"
    exit 2
fi

echo "Running ceph-volume to zap the device $OSD_DEV before use..."
ceph-volume lvm zap $OSD_DEV
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to zap $OSD_DEV. Exitting"
    exit 3
fi

if [ ! -z "$OSD_JOURNAL_DEV" ]; then
  echo "Running ceph-volume to zap the journal device $OSD_JOURNAL_DEV before use..."
  ceph-volume lvm zap $OSD_JOURNAL_DEV
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to zap $OSD_JOURNAL_DEV. Exitting"
    exit 3
  fi
fi


echo "Running ceph-volume to prepare $OSD_DEV"
if [ -z "$OSD_JOURNAL_DEV" ]; then
  ceph-volume lvm prepare --bluestore --data $OSD_DEV
else
  ceph-volume lvm prepare --bluestore --data $OSD_DEV --block.db $OSD_JOURNAL_DEV
fi

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to prepare $OSD_DEV as a bluestore device. Exitting"
    exit 3
fi
  

echo "Current list of volumes:"
ceph-volume lvm list --format json

echo <<EOF
Please look at the lvm list above and identify the index associated with the
newly created volume. This numerical index needs to be passed into the
corresponding OSD in the environment variable "OSD_ID"

EOF
