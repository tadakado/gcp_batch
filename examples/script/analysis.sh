#!/bin/bash
# Copyright (c) 2019 Tadashi Kadowaki.

# activate python environment
. ~/miniconda3/etc/profile.d/conda.sh
conda activate py3

# execute command with argumetns from the queue 
eval python -u $*
