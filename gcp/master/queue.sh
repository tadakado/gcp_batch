#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# register analysis parameters into Pub/Sub queue

##### args

while :; do
    if [ "$1" == -c ]; then
        CLEAR_QUEUE=yes
        shift 1
    elif [ "$1" == -d ]; then
        DELETE_QUEUE=yes
        shift 1
    elif [ "$1" == -n ]; then
        DRY_RUN=yes
        shift 1
    else
        break
  fi
done

ANALYSIS_NAME=$1

echo $ANALYSIS_NAME

if [ "$ANALYSIS_NAME" == "" ]; then
    echo "Usage: [-c] [-d] [-n] <analysis name>"
    echo "  -c: clear queue"
    echo "  -d: delete existing queue"
    echo "  -n: dry run"
    echo "Queue messages can be provided by STDIN. (One message per line)"
    exit 1
fi

## create pubsub

CREATE_QUEUE=yes

if [ "$DELETE_QUEUE" == yes ]; then
    if [ "$DRY_RUN" == yes ]; then
        echo gcloud pubsub subscriptions delete q-$ANALYSIS_NAME
        echo gcloud pubsub topics delete q-$ANALYSIS_NAME
    else
        gcloud pubsub subscriptions delete q-$ANALYSIS_NAME
        gcloud pubsub topics delete q-$ANALYSIS_NAME
    fi
fi

if [ "$DRY_RUN" == yes ]; then
    echo gcloud pubsub topics create q-$ANALYSIS_NAME
    echo gcloud pubsub subscriptions create q-$ANALYSIS_NAME --topic=q-$ANALYSIS_NAME
else
    gcloud pubsub topics list | grep "q-$ANALYSIS_NAME$" || \
        gcloud pubsub topics create q-$ANALYSIS_NAME > /dev/null
    gcloud pubsub subscriptions list | grep "q-$ANALYSIS_NAME$" || \
        gcloud pubsub subscriptions create q-$ANALYSIS_NAME --topic=q-$ANALYSIS_NAME > /dev/null
fi

if [ "$CLEAR_QUEUE" == yes -a "$DRY_RUN" != yes ]; then
    while :; do
        out=`gcloud pubsub subscriptions pull q-$ANALYSIS_NAME --auto-ack --limit=999 --format="value(DATA)"`
        if [ "$out" == "" ]; then
            break
        fi
    done
fi

while read MSG; do
    if [ "$DRY_RUN" == yes ]; then
        echo gcloud pubsub topics publish q-$ANALYSIS_NAME "--message=$MSG"
    else
        echo $MSG
        gcloud pubsub topics publish q-$ANALYSIS_NAME "--message=$MSG"
    fi
done
