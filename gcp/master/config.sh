# Copyright (c) 2016,2017,2018,2019 Tadashi Kadowaki.

SCRIPT=`basename $0`

# enable to check "git status"
#VERSION_CHECK=yes

# default zones to be used
# balance the number of entries between regions by repeating them
_ZONES_=(us-west1-a us-west1-b us-west1-c
         us-central1-b us-central1-c us-central1-c
         us-east1-b us-east1-c us-east1-d) # default zones

if [ "$SCRIPT" == "batch.sh" ]; then
    PREEMPTIBLE=yes       # use preemptilbe instance
    DISK_SIZE=10GB        # disk size
    LOCAL_SSD=no          # mount local-ssd
    ZONES=(${_ZONES_[@]}) # zones to be used
    SCRIPTS={script,data} # scripts to be uploaded
fi

if [ "$SCRIPT" == "monitor.sh" ]; then
    MACHINE_TYPE=f1-micro # machine type
    PREEMPTIBLE=no        # not use preemptilbe instance
    DISK_SIZE=10GB        # disk size
    ZONE=us-west1-b       # zone for the monitor instance
    ZONES=(${_ZONES_[@]}) # zones to be used
fi
