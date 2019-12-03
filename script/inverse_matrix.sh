#!/bin/bash
# Copyright (c) 2019 Tadashi Kadowaki.

# show and drop a meaningless argument
echo $1
shift 1

# activate python environment
. ~/miniconda3/etc/profile.d/conda.sh
conda activate py3

# results will be stored in results/npz
mkdir results/npz

# execute script/inverse_matrix.py with argumetns from the queue 
python script/inverse_matrix.py $*
