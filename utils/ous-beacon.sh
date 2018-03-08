#!/bin/bash

# VCF Filtering defaults
FILTER_EXE=filter_indb.py
FILTER_OPTS=""

# VCF conversion defaults
REF=GRCh37
TABLE_NAME=OUSAMG
SQL_FILE="beaconData.$REF.sqlite"

# Docker defaults
DOCKER=$(which docker)
IMAGE_NAME=ousamg/beacon
IMAGE_VER=0.1
SQL_DEST=/var/www/html/beacon/ousBeacon/beaconData.GRCh37.sqlite
CONF_DEST=/var/www/html/beacon/ousBeacon/beacon.conf

function backup_db() {
    target_file=$1
    if [[ -e $target_file ]]; then
        old_db="$target_file.$(date +%Y%m%d-%H%M%S)"
        mv $target_file $old_db
        echo "Backed up $target_file file to $old_db"
    fi
}

function show_help() {
    if [[ ! -z $1 ]]; then
        echo $1
    fi
    echo
    # keep old arg string for reference when re-adding functionality
    # echo "    usage: $0 < -v|--vcf VCF_FILE || -r|--run > [ -c|--config BEACON_CONF -q|--sqlite SQL_FILE ]"
    echo "    usage: $0 < -v|--vcf VCF_FILE >"
    echo
    exit 1
}

while getopts ":v:f:t:h" opt; do
    case "$opt" in
        v) VCF_FILE="$OPTARG"; ACTION=convert ;;
        f) VCF_FILE="$OPTARG"; ACTION=filter ;;
        t) FILTER_THRESH="$OPTARG" ;;
        :) show_help "Missing argument value: -$OPTARG" ;;
        ?) show_help "Invalid argument: -$OPTARG" ;;
        *) show_help ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    echo "You must specify either -v|--vcf to convert a VCF or -r|--run to start the beacon"
    exit 1
fi

# if [[ ! -f $BEACON_EXE ]]; then
#     echo "Cannot find beacon executable: '$BEACON_EXE', exiting"
#     exit 1
# fi

if [[ "$ACTION" == "convert" ]]; then
    # if [[ $(dirname $BEACON_EXE) != $(dirname $SQL_FILE) ]]; then

    temp_sql="$(dirname $BEACON_EXE)/$(basename $SQL_FILE)"
    echo "temp_sql: $temp_sql"
    backup_db $temp_sql
    echo "$(date "+%Y-%m-%d %H:%M:%S")  Converting $VCF_FILE to $SQL_FILE..."
    echo
    $BEACON_EXE $REF $TABLE_NAME $VCF_FILE
    if [[ $? != 0 ]]; then
        echo "Exiting failed attempt" >&2
        exit 1
    fi
    if [[ "$temp_sql" != "$SQL_FILE" ]]; then
        backup_db $SQL_FILE
        cp $temp_sql $SQL_FILE
    fi
    echo
    echo "$(date "+%Y-%m-%d %H:%M:%S")  Finished creating new $SQL_FILE"
elif [[ "$ACTION" == "filter" ]]; then
    WD=$(dirname $0)
    if [[ ! -z $DEBUG ]]; then
        FILTER_OPTS="$FILTER_OPTS --debug"
    elif [[ ! -z $VERBOSE ]]; then
        FILTER_OPTS="$FILTER_OPTS --verbose"
    fi

    if [[ ! -z $FILTER_THRESH ]]; then
        FILTER_OPTS="$FILTER_OPTS -t $FILTER_THRESH"
    fi

    $WD/$FILTER_EXE -f $VCF_FILE $FILTER_OPTS

    # TODO re-implement later
# elif [[ "$ACTION" == "run" ]]; then
#     if [[ ! -f $SQL_FILE ]]; then
#         echo "Unable to find SQLite file: '$SQL_FILE'. Check it exists or specify a new location with -q|--sql"
#         exit 1
#     elif [[ ! -f $BEACON_CONF ]]; then
#         echo "Unable to find beacon.conf file: '$BEACON_CONF'. Check it exists or specify a new location with -c|--conf"
#         exit 1
#     fi
#
#     echo "$DOCKER run -d -v $SQL_FILE:$SQL_DEST -v $BEACON_CONF:$CONF_DEST --restart=always --name ous_beacon -p 8080:80 $IMAGE_NAME:$IMAGE_VERSION"
else
    echo "Unsupported action somehow: '$ACTION'"
    exit 1
fi
