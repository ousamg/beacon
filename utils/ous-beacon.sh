#!/bin/bash

# Beacon defaults
# query is in https://github.com/maximilianh/ucscBeacon, but is hard coded to write sqlite files to its own directory
# If you change BEACON_EXE location, be aware
BEACON_EXE=./query
BEACON_CONF=beacon.conf

# VCF conversion defaults
REF=GRCh37
TABLE_NAME=OUSAMG
SQL_FILE="beaconData.$REF.sqlite"

# Docker defaults
DOCKER=$(which docker)
IMAGE_NAME=eipm/beacon
IMAGE_VERSION=1.0.0
DOCKER_WD=
SQL_DEST=/var/www/html/beacon/ucscBeacon/beaconData.GRCh37.sqlite
CONF_DEST=/var/www/html/beacon/ucscBeacon/beacon.conf

function backup_db() {
    target_file=$1
    if [[ -e $target_file ]]; then
        old_db="$target_file.$(date +%Y%m%d-%H%M%S)"
        mv $target_file $old_db
        echo "Backed up $target_file file to $old_db"
    fi
}

function show_help() {
    echo
    echo "    usage: $0 < -v|--vcf VCF_FILE || -r|--run > [ -c|--config BEACON_CONF -q|--sqlite SQL_FILE ]"
    echo
    exit 1
}

OPTS=$(getopt -o v:rc:q:h --long vcf:,run,conf:,sqlite:,help -n 'ous-beacon' -- "$@")

while true; do
    case "$1" in
        -v | --vcf) VCF_FILE="$2"; ACTION=convert ; shift 2 ;;
        -r | --run) ACTION=run; shift ;;
        -c | --conf) BEACON_CONF="$2"; shift 2 ;;;
        -q | --sqlite) SQL_FILE="$2"; shift 2 ;;
        -h | --help) show_help ; shift ;;
        --) shift ; break ;;
        *) break ;;
    esac
done

if [[ -z "$ACTION" ]]; then
    echo "You must specify either -v|--vcf to convert a VCF or -r|--run to start the beacon"
    exit 1
fi

if [[ ! -f $BEACON_EXE ]]; then
    echo "Cannot find beacon executable: '$BEACON_EXE', exiting"
    exit 1
fi

if [[ "$ACTION" == "convert" ]]; then
    if [[ $(dirname $BEACON_EXE) != $(dirname $SQL_FILE) ]]; then

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
elif [[ "$ACTION" == "run" ]]; then
    if [[ ! -f $SQL_FILE ]]; then
        echo "Unable to find SQLite file: '$SQL_FILE'. Check it exists or specify a new location with -q|--sql"
        exit 1
    elif [[ ! -f $BEACON_CONF ]]; then
        echo "Unable to find beacon.conf file: '$BEACON_CONF'. Check it exists or specify a new location with -c|--conf"
        exit 1
    fi

    echo "$DOCKER run -d -v $SQL_FILE:$SQL_DEST -v $BEACON_CONF:$CONF_DEST --restart=always --name ous_beacon -p 8080:80 $IMAGE_NAME:$IMAGE_VERSION"
else
    echo "Unsupported action somehow: '$ACTION'"
    exit 1
fi
