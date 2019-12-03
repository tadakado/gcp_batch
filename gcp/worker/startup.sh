#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# setup the analysis environment and pass the control to run.sh

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance"

rm -f /done

## get metadata
MACHINE_TYPE=`basename $(curl -s -H "Metadata-Flavor: Google" $METADATA_URL/machine-type)`
ZONE=`basename $(curl -s -H "Metadata-Flavor: Google" $METADATA_URL/zone)`
BOGO=`grep bogo /proc/cpuinfo  | tail -1 | cut -d: -f2 | tr -d " "`
for v in DEBUG RESUME LOCAL_SSD USER GS_URI ANALYSIS_NAME RUN_DIRECT COMMAND; do
    eval export $v=\"`curl -s -H "Metadata-Flavor: Google" $METADATA_URL/attributes/$v`\"
done
INSTANCE=$HOSTNAME
if [ "$LOCAL_SSD" == yes ]; then SSD=LOCAL_SSD; else SSD=NO_SSD; fi

## save for resume
> /home/env.sh
for v in MACHINE_TYPE INSTANCE ZONE BOGO DEBUG RESUME SSD USER GS_URI ANALYSIS_NAME RUN_DIRECT COMMAND; do
    eval echo $v=\\\"'$'$v\\\" >> /home/env.sh
done

## log host information
gcloud logging write instance-up "Up: $ZONE $INSTANCE $BOGO"

## setup analysis folder
useradd -m $USER
su $USER -c "mkdir /home/$USER/Batch"
cd /home/$USER/Batch
cp_ok=no
gsutil cp $GS_URI/$ANALYSIS_NAME/run/script.tar.bz2 . > /dev/null 2>&1 && cp_ok=yes
if [ "$cp_ok" == yes ]; then
    ## extract programs
    chown $USER:$USER script.tar.bz2
    su $USER -c "tar xjf script.tar.bz2"
    su $USER -c "mkdir results"
    ## mount SSD
    if [ -b /dev/sdb ] ; then
        mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb
        mount -o discard,defaults /dev/sdb results
    fi
    chmod 1777 results
    ## extract temporal results if exist
    ls_ok=no
    gsutil ls $GS_URI/$ANALYSIS_NAME/run/results/$INSTANCE.tar.bz2 > /dev/null 2>&1 && ls_ok=yes
    if [ "$ls_ok" == yes ]; then
        if [ "$RESUME" == yes ]; then
            gsutil cp $GS_URI/$ANALYSIS_NAME/run/results/$INSTANCE.tar.bz2 - |
                tar xjvf - -C results
        fi
        gsutil rm $GS_URI/$ANALYSIS_NAME/run/results/$INSTANCE.tar.bz2 > /dev/null 2>&1
    fi
    ## register host
    echo `date +%s,%c`,up,$INSTANCE,$MACHINE_TYPE,$ZONE,$SSD | gsutil cp - $GS_URI/$ANALYSIS_NAME/run/workers/$INSTANCE
    ## run user command
    if [ "$RUN_DIRECT" == yes ]; then
        su $USER -c "$COMMAND >> log.txt 2>&1"
    else
        su $USER -c "gcp/worker/run.sh $COMMAND >> log.txt 2>&1"
    fi
fi

touch /done
if [ "$DEBUG" != yes ]; then
    shutdown -h now
fi
