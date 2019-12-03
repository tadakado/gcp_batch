#!/bin/bash
# Copyright (c) 2019 Tadashi Kadowaki.

newanalysis=yes
newtarget=yes
confirm=yes

ANALYSIS_NAME=`basename $0 .sh`

### activate python environment

. ~/miniconda3/etc/profile.d/conda.sh
conda activate py3

###

PROJECT_ID=xxxxxxxx
ZONE=us-west1-b

### Analysis settings

folder=results

nsampling=50

if [ "$newanalysis" == yes ]; then
    rm -f -r results data
    mkdir -p results data log
    if [ "$newtarget" != yes ]; then
        echo use existing target configulations
        cp dataset/Run11/DATA_*.npz data
    fi
fi

# Prep & Run

param_set=(1-2-3 1-2-4 1-3-7 2-5-10)

analysis_param_0="\"{'n':100}\""

setparams () {
    IFS=- read A B C <<< $1
    save="\"tm.save('data/DATA_$A-$B')\""
    load="\"tm.load('data/DATA_$A-$B');param['tm_data']=tm.data\""
    analysis_param_1="\"{}\""
    analysis_param_2="\"{'a':{'b':$(($A*$B+$C))}}\""
    analyses=(
        "script/run.py run data/abc_$A-$B-$C $analysis_param_1"
        "script/run.py run data/def_$A-$B-$C $analysis_param_2"
    )
}

if [ "$newanalysis" == yes ]; then
    if [ "$newtarget" == yes ]; then
        echo generate new target configulations
        for p in ${param_set[@]}; do
            setparams $p
            eval python script/run.py prep $folder $analysis_param_0 $save
        done
        for p in ${param_set[@]}; do
            setparams $p
            eval python script/run.py prep $folder abc_$A-$B-$C $analysis_param_1 $load
            eval python script/run.py prep $folder def_$A-$B-$C $analysis_param_2 $load
        done
    fi
    cp $folder/*.pickle.bz2 data
fi

### Queue settings

IMAGE=conda-2019
IMAGE_PROJECT=$PROJECT_ID
MACHINE_TYPE=n1-highcpu-64
N_INSTANCES=100
USER=alphonse
GS_URI=gs://xxxxxxxx/analysis
COMMAND="script/analysis.sh"

echo register batch commands to queue

> log/queue.txt
for r in `seq 0 $((nsampling-1))`; do
    for p in ${param_set[@]}; do
        setparams $p
        for a in "${analyses[@]}"; do
            echo $a sampling_no=$r >> log/queue.txt
        done
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
