### Ceph cluster administration tools

This directory contains content associated with Ceph cluster creation

1) Scripts under ceph_initialize
2) Initial cluster configuration files under etc. This simply a location
to copy the /etc/ceph directory from the initial ceph mon, so that the
subsequent members of the cluster can communicate amongst each other in the
cluster.
3) A set of tuning parameters for sysctl.conf, This file is meant to be
appended to the the host's /etc/sysctl.conf and imediately loaded with
"sysctl --system", or else it will be picked up at reboot.

## Support Scripts ##

There are 2 scripts in the ceph_initialize directory that support
initial creation of a Ceph cluster. The procedure is based on this document:
https://geek-cookbook.funkypenguin.co.nz/ha-docker-swarm/shared-storage-ceph/

That document is somewhat out of date with respect to the OSD service,
which no longer supports the osd_ceph_disk entrypoint properly. So there
are changes based on this trouble ticket:
https://github.com/ceph/ceph-container/issues/1395

The scripts are:

1) initialize_cluster_creds.sh - this script is used to copy the initial
cluster credentials generated in /etc/ceph by the first ceph monitor that
is brought up, and installs them in the local /etc/ceph directory. Please
read the documentation at the start of the script for details

2) initialize_osd.sh - this script handles setting up additional cluster
credentials for the OSD service, as well as the rgw (rados gateway) service,
and initializes the partition that will be used by the OSD service. This
latter part handles the incompatibility with the osd_deph_disk endpoint
that is discussed in the github trouble ticket. This script can be run
at any time after the initialize_cluster_creds.sh script, but before the
OSD and RGW services are brought up. Please read the initial part of the
script for directions - the output from this script includes the numerical
ID of the newly initialized ceph volume, which needs to be passed to the
ceph OSD service that is brought up on that node.

## Procedures for the scripts ##

In the current environment at Berkeley, the ceph-shell containers are ceph/daemon
images that have all of the necessary mounts to access the persistent data in
/etc/ceph and /var/lib/ceph, as well as the underlying directories needed for
working with disk partitions and logical volumes. It also mounts the /mnt/data1/ceph
directory where shared ceph administrative files are kept. There should be one
instance running on every host. Within the ceph-shell container, /mnt/ceph mounts
the underlying /mnt/data1/ceph directory. So /mnt/ceph/etc is a location where the
shared /etc/ceph files can be written/read and /mnt/ceph/ceph_initialize has the
scripts for initialization.

It is recommended to have a seperate partition for ceph's /var/log and /var/lib
so that any messages that may fill up /var do not use up all space on the root
partition of the host. If there is a separate /var/ partition for docker's files
this will take care of /var/log within the containers. However ceph will complain
if /var/lib/ceph doesn't enough space to store the databases associated with the
ceph cluster services.

The general procedure for bringing a ceph cluster works like this:

1) Set aside a number of systems for the Ceph monitor, manager, metadata service,
OSD and rados gateway services. The monitor services seem to be a the core
service that manages/oversees the other services. A single ceph monitor service
is the first service to be brought up, which will generate some initial cluster
credentials, which need to be copied to the other nodes before their ceph
monitors are brought up (see the initialize_cluster_creds.sh script). There should
be an odd number of monitor instances to avoid issues with quorum elections, though
you can bring up an even number and the cluster will run. For all of these nodes,
there needs to be a persistent volume for the /etc/ceph and /var/lib/ceph directories
of the running ceph services.

2) Once the initial ceph monitor is up, copy the contents of it's /etc/ceph directory
to a directory that all of the other nodes can access when running the initialize-*
scripts. Make sure that when the initialize scripts are run, they have the /etc/ceph and
/var/lib/ceph directories mounted which the mon,mgr,mds,osd and rgw services will be using
as well - using the existing ceph-shell container on the host ensures that this is already
setup. The mon,mgr and mds services can come up after the initialize_cluster_creds.sh
script is run. The osd and rgw services require that the initialize_osd.sh script be run
first to initialize the storage partition and setup bootstrap service credentials.

2.1) The osd and mon services require host specific environment variable settings at
startup, and cannot be setup as an autoscaling service.

2.1.1) The mon service requires that the local IP address of the host be passed in as
the environment variable MON_IP at startup.

2.1.2) The osd services have a 1 to 1 correspondence between service instances and
disk partitions. The initialize_osd script will need to know the block device for the
partition, at which point it will wipe out all of the contents and setup vg/lvm and
otherwise prepare the partition for the OSD service. When it is done with initialization
the script will display a list of the volumes on the local host that are available
for use by the osd service. Find the volume number associated with the new disk partition.
The osd service needs this volume ID to be passed in as the OSD_ID environment variable
when starting the service.

3) Once the services are brought up, it should be possible to run "ceph status" within
any container that is registered into the cluster and has the ceph binaries installed.
In the current rancher environment the ceph-shell container serves this purpose - it has
all of the necessary volumes mounted for administrative functions.

4) As new instances of services are brought into the cluster steps 2 and 3 can be run to
expand the cluster.

## Creating Accounts ##

The most common accounts that will need to be created are S3 accounts, the tool for administering
this is *radosgw-admin*
http://docs.ceph.com/docs/mimic/man/8/radosgw-admin/

To get started, here is how you can create an S3 testuser account for with the access key "blah"
and the password "secret_blah"
~~~
[root@ceph02 /]# radosgw-admin user create --display-name="Test user" --uid="testuser" --access-key="blah" --secret="secret_blah"
{
    "user_id": "testuser",
    "display_name": "Test user",
    "email": "",
    "suspended": 0,
    "max_buckets": 1000,
    "subusers": [],
    "keys": [
        {
            "user": "testuser",
            "access_key": "blah",
            "secret_key": "secret_blah"
        }
    ],
    "swift_keys": [],
    "caps": [],
    "op_mask": "read, write, delete",
    "default_placement": "",
    "default_storage_class": "",
    "placement_tags": [],
    "bucket_quota": {
        "enabled": false,
        "check_on_raw": false,
        "max_size": -1,
        "max_size_kb": 0,
        "max_objects": -1
    },
    "user_quota": {
        "enabled": false,
        "check_on_raw": false,
        "max_size": -1,
        "max_size_kb": 0,
        "max_objects": -1
    },
    "temp_url_keys": [],
    "type": "rgw",
    "mfa_ids": []
}
~~~

This account is then immediately usable against the S3 service that listens on port 7480.

## Basic Tuning ##

The rados-gateway hosts will be performing a lot of network transfers and benefit
from having system parameters tuned for networking intensive use. An initial set of
tuning parameters borrowed from Minio, FasterData and other sources is in the
append2sysctl.conf file. Appending it to the host environment's /etc/sysctl.conf and
then reloading sysctl.conf with "sysctl --system" is recommended, to make sure that
there is enough buffer space allocated to the networking stack and other tuning
parameters are in place

The following guidelines are suggested by Redhat for production Ceph deployments

1. Ceph Monitor services should ideally be run on a machine separate from OSD
osts to avoid I/O contention. At the very least they should operate against separate
drives on the same host
1.1 Ceph Monitor services use RocksDB for persistent storage, which is built on levelDB.
The levelDB files are kept under /var/lib/ceph and should be on a partition which
performs well for many small random I/O transactions ( SSD ).
1.2 The partition containing /var/lib/ceph should be on a different physical disk from the partition that contains the OSD data.
2. Ceph Metadata services should also be seperate from OSD hosts to avoid I/O contention.
At very least they should run against different disks.
3. There should be no more than 1 OSD service assigned to a partition
4. Having too many Ceph Mon services will slow down performance because of the need to
replicate database updates across more hosts
5. If you can afford SOME SSD drives, it pays to create OSDs with a spinning disk data
partition and an SSD journal partition
6. Create different crush map rules for different classes (SATA, SAS, SSD) of storage,
and use these rules when creating pools based on the worklow that applies

Relevant links:
https://access.redhat.com/documentation/en-us/red_hat_ceph_storage/3/html-single/storage_strategies_guide/index
https://docs.ceph.com/docs/master/start/hardware-recommendations/

## Use of SSD drives for storage and journals ##

https://ceph.com/community/new-luminous-bluestore/

    When setting up partitions for OSDs, the fastest configuration is pure SSD. If this is not available then
with bluestore, it recommended to have an SSD partition for storing the Bluestore metadata and journal. If you
do not have any SSDs, then just use a standard partition for the OSD. Here is how a partition is prepared
if there are available SSD partitions:

ceph-volume lvm prepare --bluestore --data $OSD_DEV

   If there is an SSD partition available then assuming the path to the SSD
partition is in $OSD_JOURNAL_PARTITION this how it is used in the prepare
command:

ceph-volume lvm prepare --bluestore --data $OSD_DEV --block.db $OSD_JOURNAL_DEV

   If the data partition is SSD already, then simply using the first form, without
a --block.db parameter, is enough.

## Assigning Ceph pools to different types of storage ##
   
https://ceph.com/community/new-luminous-crush-device-classes/

   When OSDs are brought online, Ceph tries to identify the underlying device type
(SSD, spinning drive, nvme) by querying the kernel for information about the partition.
If Ceph is able to identify the storage as SSD, hard disk or nvme then this will be
visible in the device class displayed in the output from "caph osd tree"
~~~
[root@ceph01 /]# ceph osd tree
ID  CLASS WEIGHT   TYPE NAME       STATUS REWEIGHT PRI-AFF 
 -1       16.30438 root default                            
 -3        4.07610     host ceph02                         
  0   hdd  4.01070         osd.0       up  1.00000 1.00000 
  1   ssd  0.06540         osd.1       up  1.00000 1.00000 
-10        4.07610     host ceph03                         
  4   hdd  4.01070         osd.4       up  1.00000 1.00000 
  5   ssd  0.06540         osd.5       up  1.00000 1.00000 
 -5        4.07610     host ceph04                         
  2   hdd  4.01070         osd.2       up  1.00000 1.00000 
  3   ssd  0.06540         osd.3       up  1.00000 1.00000 
-13        4.07610     host ceph05                         
  6   hdd  4.01070         osd.6       up  1.00000 1.00000 
  7   ssd  0.06540         osd.7       up  1.00000 1.00000 
[root@ceph01 /]# 
~~~
   Note that in the LBL storage cluster, the hdd class is actually hybrid ssd journal +
spinning drive data partition.


   In the installations at LBL so far, ceph has not been able to identify SSD partitions
as SSD, and has put them in the HDD class. This can be fixed manually with the following
commands:
~~~
$ ceph osd crush rm-device-class osd.2 osd.3
done removing class of osd(s): 2,3
$ ceph osd crush set-device-class ssd osd.2 osd.3
set osd(s) 2,3 to class 'ssd'
~~~

   Once device classes are in place for OSDs, Crush rules can be defined to assign
storage pools to the relevant OSDs for the workload. For example, this rule called
"fast" applies to replicated pools, and assigns the pool to the SSD device class:
~~~
ceph osd crush rule create-replicated fast default host ssd
~~~

   This next rule named "datastorage" would be used to route the pool to only the
conventional HDD OSDs 
~~~
ceph osd crush rule create-replicated datastorage default host hdd
~~~

   The set of Crush rules in operation can be viewed using the osd crush rule dump
subcommand of the ceph commandline tool:
~~~
[root@ceph01 /]# ceph osd crush rule dump
[
    {
        "rule_id": 0,
        "rule_name": "replicated_rule",
        "ruleset": 0,
        "type": 1,
        "min_size": 1,
        "max_size": 10,
        "steps": [
            {
                "op": "take",
                "item": -1,
                "item_name": "default"
            },
            {
                "op": "chooseleaf_firstn",
                "num": 0,
                "type": "host"
            },
            {
                "op": "emit"
            }
        ]
    },
    {
        "rule_id": 1,
        "rule_name": "fast",
        "ruleset": 1,
        "type": 1,
        "min_size": 1,
        "max_size": 10,
        "steps": [
            {
                "op": "take",
                "item": -9,
                "item_name": "default~ssd"
            },
            {
                "op": "chooseleaf_firstn",
                "num": 0,
                "type": "host"
            },
            {
                "op": "emit"
            }
        ]
    },
    {
        "rule_id": 2,
        "rule_name": "datastorage",
        "ruleset": 2,
        "type": 1,
        "min_size": 1,
        "max_size": 10,
        "steps": [
            {
                "op": "take",
                "item": -2,
                "item_name": "default~hdd"
            },
            {
                "op": "chooseleaf_firstn",
                "num": 0,
                "type": "host"
            },
            {
                "op": "emit"
            }
        ]
    }
]
~~~

   Note that the "ssd" and "hdd" parameters to the crush rules we defined are
reflected in the "take" step which assigns the pool to "default~ssd" and
"default~hdd" shadow hierarchies. Please see this page for more explanation:

https://docs.ceph.com/docs/master/rados/operations/crush-map/

   The storage strategies guide explains the use of device classes and pools
more thproughly:
https://access.redhat.com/documentation/en-us/red_hat_ceph_storage/3/html-single/storage_strategies_guide/index

   Once the crush rules are defined, then the rule is invoked during the
pool creation command as follows:

~~~
ceph osd pool create default.rgw.buckets.index 4 4 replicated fast
~~~

  Or else the rule is assigned to an existing pool to migrate it:
~~~
ceph osd pool set defalt.rgw.buckets.index crush_rule fast
~~~

   In this case, we have made sure that the object gateway (S3) indexes are kept
on SSDs to speed up metadata lookup/updates

   To ensure that other pools are assigned specifically to either SSD or HDD, and
not scattered randomly across both device classes, it is a good idea to explicitly
create the pools with the applicable rules, or else explicitly assign the pool to
a crush rule.

# Setting up SSD cache tier for RadosGW #

   Setup an SSD pool to be a fast write cache for S3 operations. Note that the cache
mode is "readproxy" which uses the cache _only_ for writes. The read performance is
actually perfectly adequate, we just need better write performance:

   Based on the https://docs.ceph.com/docs/master/rados/operations/cache-tiering/
   with additional notes from https://github.com/maricaantonacci/ceph-tutorial/wiki/Enable-Cache-Tier
~~~
[root@ceph01 ceph]# ceph osd pool create default.rgw.buckets.cache 4 4 replicated fast
pool 'default.rgw.buckets.cache' created
[root@ceph01 ceph]# rados df
POOL_NAME                              USED OBJECTS CLONES COPIES MISSING_ON_PRIMARY UNFOUND DEGRADED  RD_OPS      RD  WR_OPS      WR USED COMPR UNDER COMPR 
.rgw.root                           768 KiB       4      0     12                  0       0        0      76  76 KiB       4   4 KiB        0 B         0 B 
default.rgw.buckets.cache               0 B       0      0      0                  0       0        0       0     0 B       0     0 B        0 B         0 B 
default.rgw.buckets.data                0 B       0      0      0                  0       0        0  825002 602 MiB 2035630 199 MiB        0 B         0 B 
default.rgw.buckets.data-replicated     0 B       0      0      0                  0       0        0 2904624 2.1 GiB 7177496  17 GiB        0 B         0 B 
default.rgw.buckets.index               0 B       0      0      0                  0       0        0 5696623 5.4 GiB 2822840 1.8 GiB        0 B         0 B 
default.rgw.buckets.non-ec              0 B       0      0      0                  0       0        0    1073 680 KiB     299 258 KiB        0 B         0 B 
default.rgw.control                     0 B       8      0     24                  0       0        0       0     0 B       0     0 B        0 B         0 B 
default.rgw.log                         0 B     207      0    621                  0       0        0 1560563 1.5 GiB 1039834 2.1 MiB        0 B         0 B 
default.rgw.meta                    768 KiB       5      0     15                  0       0        0    6619 5.2 MiB     787 278 KiB        0 B         0 B 

total_objects    224
total_used       56 GiB
total_avail      16 TiB
total_space      16 TiB
[root@ceph01 ceph]# ceph osd tier add default.rgw.buckets.data default.rgw.buckets.cache
pool 'default.rgw.buckets.cache' is now (or already was) a tier of 'default.rgw.buckets.data'
[root@ceph01 ceph]# ceph osd tier cache-mode default.rgw.buckets.cache readproxy
set cache-mode for pool 'default.rgw.buckets.cache' to readproxy
[root@ceph01 ceph]# ceph osd tier set-overlay default.rgw.buckets.data default.rgw.buckets.cache
overlay for 'default.rgw.buckets.data' is now (or already was) 'default.rgw.buckets.cache'
[root@ceph01 /]# ceph osd pool set default.rgw.buckets.cache hit_set_type bloom
set pool 13 hit_set_type to bloom
[root@ceph01 /]# ceph osd pool set default.rgw.buckets.cache hit_set_count 1   
[root@ceph01 ceph]# ceph osd pool set default.rgw.buckets.cache hit_set_period 300
set pool 13 hit_set_period to 300
[root@ceph01 /]# ceph osd pool set default.rgw.buckets.cache target_max_bytes 500000000000
set pool 13 target_max_bytes to 500000000000
[root@ceph01 ceph]# ceph osd pool set default.rgw.buckets.cache target_max_objects 500000
set pool 13 target_max_objects to 500000
[root@ceph01 /]# ceph osd pool set default.rgw.buckets.cache min_read_recency_for_promote 1
set pool 13 min_read_recency_for_promote to 1
[root@ceph01 /]# ceph osd pool set default.rgw.buckets.cache min_write_recency_for_promote 1
set pool 13 min_write_recency_for_promote to 1
[root@ceph01 ceph]# ceph osd pool set default.rgw.buckets.cache cache_target_dirty_ratio .01
set pool 13 cache_target_dirty_ratio to .01
[root@ceph01 ceph]# ceph osd pool set default.rgw.buckets.cache cache_target_full_ratio .02 
set pool 13 cache_target_full_ratio to .02
[root@ceph01 /]# 

~~~

   Tune the replicas to only 1, because the backing store is where data redundancy is handled:
~~~
[root@ceph01 ceph]# ceph osd pool set default.rgw.buckets.cache size 1
set pool 13 size to 1
[root@ceph01 ceph]# ceph osd dump
[snip]
pool 13 'default.rgw.buckets.cache' replicated size 1 min_size 1 crush_rule 1 object_hash rjenkins pg_num 4 pgp_num 4 autoscale_mode warn last_change 103 flags hashpspool,incomplete_clones tier_of 12 cache_mode readproxy stripe_width 0
[snip]
[root@ceph01 ceph]#
~~~
