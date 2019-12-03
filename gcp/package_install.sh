#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# a script to install packages in GCP debian instance

# wget tmux gcsfuse git
GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
echo "deb http://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y wget tmux gcsfuse git

# .tmux.conf
curl -L https://gist.github.com/tadakado/853d363dbd82eafbd69019504505e288/raw/d213d66bf81c6330dfa0549b263f0f9b723db3ca/.tmux.conf -O

# conda
curl https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O
bash Miniconda3-latest-Linux-x86_64.sh -u -b
rm Miniconda3-latest-Linux-x86_64.sh
. miniconda3/etc/profile.d/conda.sh
conda init
conda create -y -n py3 python=3.7
conda activate py3
conda install -y pytorch-cpu torchvision-cpu -c pytorch
conda install -y jupyterlab pandas seaborn mxnet
#pip install dwave-ocean-sdk
pip install papermill
