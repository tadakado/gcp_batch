#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# invoke an monitor instance

##### default settings (NOT EDIT THIS FILE BUT config.sh)

MACHINE_TYPE=f1-micro # machine type
PREEMPTIBLE=no        # not use preemptilbe instance
DISK_SIZE=10GB        # disk size
ZONE=us-west1-b       # zone for the monitor instance
ZONES=(us-west1-a us-west1-b us-west1-c
       us-central1-a us-central1-b us-central1-c us-central1-f
       us-east1-b us-east1-c us-east1-d) # zones to be used

##### load settings

SCRIPTDIR=`dirname $0`
source $SCRIPTDIR/config.sh

##### version check

if [ "$VERSION_CHECK" == yes ]; then
  source $SCRIPTDIR/version.sh
fi

##### args

while :; do
    if [ "$1" == -r ]; then
        REUSE=yes
        shift 1
    elif [ "$1" == -d ]; then
        DEBUG=yes
        shift 1
    elif [ "$1" == -D ]; then
        DELETE=yes
        shift 1
    else
        break
    fi
done

read IMAGE IMAGE_PROJECT GS_URI ANALYSIS_NAME <<< $*

if [ "$GS_URI" == "" ]; then
    echo "Usage: [-d] <image> <image-project> <gs uri> <folder>"
    echo "  -D: delete terminated instances"
    echo "  -d: debug mode"
    echo "  -r: reuse stopped instances"
  exit 1
fi

#####

GS_URI=${GS_URI%/}

INSTANCE=monitor-`echo $ANALYSIS_NAME | tr A-Z_. a-z--`

COMMAND=gcp/worker/monitor.sh
METADATA="--metadata DEBUG=$DEBUG,REUSE=$REUSE,DELETE=$DELETE,USER=$USER,GS_URI=$GS_URI,ANALYSIS_NAME=$ANALYSIS_NAME,RUN_DIRECT=yes,COMMAND=\"$COMMAND\",ZONES=\"${ZONES[@]}\" \
          --metadata-from-file startup-script=gcp/worker/startup.sh,shutdown-script=gcp/worker/shutdown.sh"
OPTS="--machine-type $MACHINE_TYPE $METADATA --service-account=default --scopes=compute-rw,storage-rw,pubsub,logging-write"
if [ "$PREEMPTIBLE" == yes ]; then
    OPTS="$OPTS --no-restart-on-failure --maintenance-policy TERMINATE --preemptible"
else
    OPTS="$OPTS --maintenance-policy MIGRATE"
fi
DISK="--image-project $IMAGE_PROJECT --image $IMAGE --boot-disk-size $DISK_SIZE --boot-disk-type pd-standard --boot-disk-device-name $INSTANCE"

status=(`gcloud compute instances list --filter="name=($INSTANCE)" --format="value(STATUS,ZONE)"`)
if [ "$status" == "" ]; then
    echo create a new instance $INSTANCE in $ZONE
    sh -c "gcloud compute instances create $INSTANCE --zone $ZONE $OPTS $DISK"
elif [ "$status" == TERMINATED ]; then
    ZONE_ORG=${status[1]}
    echo start an existing instance $INSTANCE in $ZONE_ORG
    gcloud compute instances start $INSTANCE --zone $ZONE_ORG
fi
