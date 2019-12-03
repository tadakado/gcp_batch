#!/bin/bash
# Copyright (c) 2019 Tadashi Kadowaki.

newanalysis=yes
newtarget=no
confirm=yes

### activate python environment

. ~/miniconda3/etc/profile.d/conda.sh
conda activate py3

###

PROJECT_ID=xxxxxxxx
ZONE=us-west1-b

### Analysis settings

folder=results

nsampling=100

if [ "$newanalysis" == yes ]; then
    rm -f -r results data
    mkdir -p results data log
    if [ "$newtarget" != yes ]; then
        echo use existing target configulations
        cp dataset/Run04/DATA.npz data
    fi
fi

# Prep & Run

save="\"tm.save('data/DATA')\""
load="\"tm.load('data/DATA');param['tm_data']=tm.data\""

analysis_param_00="\"{'n':100}\""
analysis_param_01="\"{'c':1,  'd':{'e':3}}\""
analysis_param_02="\"{'c':2,  'd':{'e':4}}\""

if [ "$newanalysis" == yes ]; then
    if [ "$newtarget" == yes ]; then
        echo generate new target configulations
        eval python script/run.py prep $folder $analysis_param_00 $save
    fi
    eval python script/run.py prep $folder abc $analysis_param_01 $load
    eval python script/run.py prep $folder def $analysis_param_02 $load
    eval python script/run.py prep $folder ghi $analysis_param_03 $load
    cp $folder/*.pickle.bz2 data
fi

analysis_param="\"{}\""
analyses=(
    "script/run.py run data/abc $analysis_param"
    "script/run.py run data/def $analysis_param"
    "script/run.py run data/ghi $analysis_param"
)

### Queue settings

IMAGE=conda-2019
IMAGE_PROJECT=$PROJECT_ID
MACHINE_TYPE=n1-highcpu-64
N_INSTANCES=100
USER=alphonse
GS_URI=gs://xxxxxxxx/analysis
ANALYSIS_NAME=Run07
COMMAND="script/analysis.sh"

echo register batch commands to queue

> log/queue.txt
for r in `seq 0 $((nsampling-1))`; do
    for a in "${analyses[@]}"; do
        echo $a sampling_no=$r >> log/queue.txt
    done
done
gcp/master/queue.sh -c $ANALYSIS_NAME < log/queue.txt 1> log/queue.log 2> log/queue.err &

if [ "$newanalysis" == yes ]; then
    if [ "$confirm" == yes ]; then
        echo start 1 instance instead of $N_INSTANCES instances to confirm everything goes well
        gcp/master/batch.sh -f $IMAGE $IMAGE_PROJECT $MACHINE_TYPE 1 $USER $GS_URI $ANALYSIS_NAME "$COMMAND" 1> log/batch.log 2> log/batch.err
        while :; do
            read -p "input 'GO' to continue: " go
            if [ "$go" == "GO" ]; then break; fi
        done
    fi

    echo start $N_INSTANCES instances

    gcp/master/batch.sh -f $IMAGE $IMAGE_PROJECT $MACHINE_TYPE $N_INSTANCES $USER $GS_URI $ANALYSIS_NAME "$COMMAND" 1> log/batch.log 2> log/batch.err

    echo start monitor

    gcp/master/monitor.sh -r $IMAGE $IMAGE_PROJECT $GS_URI $ANALYSIS_NAME 1> log/monitor.log 2> log/monitor.err
else
    echo RUN INSTANCES MANUALLY!!!
fi
