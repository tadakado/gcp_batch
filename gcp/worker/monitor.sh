#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# monitor instances and restart stopped ones

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"

cd $HOME/Batch

## get metadata
for v in DEBUG REUSE DELETE GS_URI ANALYSIS_NAME ZONES; do
    eval export $v=\"`curl -s -H "Metadata-Flavor: Google" $METADATA_URL/attributes/$v`\"
done
ZONES=($ZONES)
OPTS=`gsutil cat $GS_URI/$ANALYSIS_NAME/run/INSTANCE_OPTIONS.txt`

echo ============================================================
date
for e in REUSE GS_URI ANALYSIS_NAME OPTS; do
    eval echo $e: '$'$e
done
echo ZONES: ${ZONES[@]}

count=0
while :; do
    n_up=0
    for e in `gsutil ls $GS_URI/$ANALYSIS_NAME/run/workers/worker-* 2> /dev/null`; do
        ## status from the batch system
        status=`gsutil cat $e`
        IFS=, read TIME_SEC TIME_STR RUN_STATUS INSTANCE MACHINE_TYPE ZONE_ORG SSD <<< $status
        if [ "$DEBUG" == yes ]; then echo DEBUG: ---------- `date` ----------; echo DEBUG: $e; echo DEBUG: $status; fi
        INSTANCE=`basename $e`
        TIME_DURATION=$((`date +%s` - TIME_SEC))
        if [ "$RUN_STATUS" != down ]; then n_up=$((n_up + 1)); fi
        ## status from GCP
        status=(`gcloud compute instances list --filter="name=($INSTANCE)" --format="value(STATUS,ZONE)"`)
        if [ "$DEBUG" == yes ]; then echo DEBUG: ${status[@]}; fi
        ZONE_ORG=${status[1]}
        ZONE=${ZONES[$(((RANDOM % ${#ZONES[@]})))]}
        command_delete="gcloud compute instances delete $INSTANCE --zone $ZONE_ORG --delete-disks all -q"
        command_create="gcloud compute instances create $INSTANCE --zone $ZONE $OPTS --boot-disk-device-name $INSTANCE"
        command_start="gcloud compute instances start $INSTANCE --zone $ZONE_ORG"
        if [ "$RUN_STATUS" == down -a "$status" == TERMINATED -a "$DELETE" == yes ]; then
            echo delete the instance $INSTANCE in $ZONE_ORG
            sh -c "$command_delete" &
            continue
        fi
        if [ "$RUN_STATUS" == unexpected-down ] || [ "$RUN_STATUS" == booting -a "$TIME_DURATION" -ge 300 ]; then
            if [ "$status" == "" ]; then
                echo create a new instance $INSTANCE in $ZONE
                command=$command_create
            elif [ "$status" == TERMINATED ]; then
                if [ "$REUSE" == yes -a "$SSD" != LOCAL_SSD ]; then
                    echo reuse the existing instance $INSTANCE in $ZONE_ORG
                    command=$command_start
                else
                    echo delete the existing instance $INSTANCE in $ZONE_ORG and create a new instance $INSTANCE in $ZONE
                    command="$command_delete; $command_create"
                fi
            else
                echo wait for the next scan of $INSTANCE in $ZONE_ORG
                continue
            fi
            if [ "$DEBUG" == yes ]; then echo DEBUG: $command; fi
            echo `date +%s,%c`,booting,$INSTANCE,$MACHINE_TYPE,$ZONE,$SSD | gsutil cp - $GS_URI/$ANALYSIS_NAME/run/workers/$INSTANCE
            sh -c "$command" &
        fi
    done
    if [ "$n_up" == 0 ]; then
        count=$((count + 1))
        if [ "$count" -ge 2 ]; then
            break
        fi
    else
        count=0
    fi
    sleep 60
done

gcloud logging write worker "Completed: $ZONE $INSTANCE $BOGO $ANALYSIS_NAME $COMMAND"
