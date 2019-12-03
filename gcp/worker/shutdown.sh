#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# upload temporal results if analysis is not completed

source /home/env.sh

if [ -e /done ]; then
    echo `date +%s,%c`,down,$INSTANCE,$MACHINE_TYPE,$ZONE,$SSD | gsutil cp - $GS_URI/$ANALYSIS_NAME/run/workers/$INSTANCE
    gcloud logging write instance-down "Down: $ZONE $INSTANCE $BOGO"
else
    echo `date +%s,%c`,unexpected-down,$INSTANCE,$MACHINE_TYPE,$ZONE,$SSD | gsutil cp - $GS_URI/$ANALYSIS_NAME/run/workers/$INSTANCE
    gcloud logging write instance-unexpected-down "Unexpected down: $ZONE $INSTANCE $BOGO"
    while :; do
        tar cjvf /tmp/results.tar.bz2 -C /home/$USER/Batch/results --exclude lost+found .
        if [ "$PIPESTATUS" == 0 ]; then
            break
        fi
    done
    gsutil cp /tmp/results.tar.bz2 $GS_URI/$ANALYSIS_NAME/run/results/$INSTANCE.tar.bz2
fi
gsutil cp /home/$USER/Batch/log.txt $GS_URI/$ANALYSIS_NAME/run/logs/${INSTANCE}_`date +%Y%m%d_%H%M%S`.txt
