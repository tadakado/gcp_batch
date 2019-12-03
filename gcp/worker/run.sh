#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# run user's command combined with parameters from Pub/Sub queue

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"

cd $HOME/Batch

COMMAND=$*

trap 'exit 1' SIGTERM

## get metadata
for v in DEBUG RESUME USER GS_URI ANALYSIS_NAME COMMAND; do
    eval export $v=\"`curl -s -H "Metadata-Flavor: Google" $METADATA_URL/attributes/$v`\"
done
INSTANCE=$HOSTNAME

echo ============================================================
date
for e in DEBUG RESUME USER GS_URI ANALYSIS_NAME COMMAND; do
    eval echo $e: '$'$e
done

GS_FOLDER=$GS_URI/$ANALYSIS_NAME
GS_RUN_FOLDER=$GS_FOLDER/run

count=0
while : ; do
    echo ------------------------------------------------------------
    date
    ## whether previous session completed or not
    queue=`gsutil cat $GS_RUN_FOLDER/params/$INSTANCE 2> /dev/null || gcloud pubsub subscriptions pull q-$ANALYSIS_NAME --auto-ack --format="value(DATA)"`
    if [ "$queue" != "" ] ; then
        PARAMETERS=$queue
        echo $PARAMETERS | gsutil cp - $GS_RUN_FOLDER/params/$INSTANCE
        ZONE=`basename $(curl -s -H "Metadata-Flavor: Google" $METADATA_URL/zone)`
        BOGO=`grep bogo /proc/cpuinfo  | tail -1 | cut -d: -f2 | tr -d " "`
        MSG="$ZONE $INSTANCE $BOGO $ANALYSIS_NAME $COMMAND $PARAMETERS"
        gcloud logging write worker "Start: $MSG"
        echo $COMMAND $PARAMETERS
        $COMMAND $PARAMETERS || continue

        ## upload results (files and dirs) & data
        gsutil -m cp -r results $GS_FOLDER/ && rm -r -f results/* 2> /dev/null
        gsutil -m cp -r data $GS_FOLDER/

        ## cleaning
        gsutil rm $GS_RUN_FOLDER/params/$INSTANCE
        gcloud logging write worker "Done: $MSG"
    else
        echo Can\'t get parameters, will try in 5 sec.
        count=$(($count + 1))
        if [ $count -gt 10 ] ; then
            echo Exceeds the limit, exiting ...
            break
        fi
    fi
    sleep 5
done

gcloud logging write worker "Completed: $ZONE $INSTANCE $BOGO $ANALYSIS_NAME $COMMAND"
