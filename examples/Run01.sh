#!/bin/bash
# Copyright (c) 2019 Tadashi Kadowaki.

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

rm -f -r results data
mkdir -p results data log

# Prep & Run

analysis_param_1="\"{'a':1}\""
analysis_param_2="\"{'a':1, 'b':{'c':3}}\""

analyses=(
    "script/run.py prep -r $folder $analysis_param_1"
    "script/run.py prep -r $folder $analysis_param_2"
)

### Queue settings

IMAGE=conda-2019
IMAGE_PROJECT=$PROJECT_ID
MACHINE_TYPE=n1-highcpu-64
N_INSTANCES=100
USER=alphonse
GS_URI=gs://xxxxxxxx/analysis
ANALYSIS_NAME=Run01
COMMAND="script/analysis.sh"

echo register batch commands to queue

> log/queue.txt
for r in `seq 0 $((nsampling-1))`; do
    for a in "${analyses[@]}"; do
        echo $a sampling_no=$r >> log/queue.txt
    done
done
gcp/master/queue.sh -c $ANALYSIS_NAME < log/queue.txt 1> log/queue.log 2> log/queue.err &

if [ "$confirm" == "yes" ]; then
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
