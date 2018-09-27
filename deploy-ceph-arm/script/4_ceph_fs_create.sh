#!/bin/bash
#
#

set -o errexit
set -o nounset
set -o pipefail
set -x
ceph osd pool create cephfs_data 64
ceph osd pool create cephfs_metadata 64
ceph fs new cephfs cephfs_metadata cephfs_data
