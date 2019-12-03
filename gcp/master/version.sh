#!/bin/bash
# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.
#
# check git status in the "script" folder

SCRIPTDIR=`dirname $0`
GITSTATUS=`(cd $SCRIPTDIR; git status --porcelain --u=no)`
if [ "$GITSTATUS" != "" ]; then
    echo Commit first!
    exit 1
fi
SHA1=`(cd $SCRIPTDIR; git rev-parse HEAD)`
