#!/bin/bash

abs_dirname() {
    if [[ -z $1 ]]; then
        SOURCE="${BASH_SOURCE[0]}"
    else
        SOURCE=$1
    fi

    # resolve $SOURCE until the file is no longer a symlink
    while [ -h "$SOURCE" ]; do
      DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
      [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    echo "$( cd -P "$( dirname "$SOURCE" )" && pwd )"
}

backup_db() {
    target_file=$1
    if [[ -e $target_file ]]; then
        old_db="$target_file.$(date +%Y%m%d-%H%M%S)"
        mv $target_file $old_db
        echo "Backed up $target_file file to $old_db"
    fi
}

docker_build() {
    $DOCKER build ${DOCKER_ARGS[@]} -t $IMAGE_NAME:$IMAGE_VER $(abs_dirname $BEACON_EXE)
}

docker_run() {
    $DOCKER run -dit --restart=always --name $CTR_NAME -p 8080:80 ${DOCKER_ARGS[@]} $IMAGE_NAME:$IMAGE_VER
}

show_help() {
    # Print a message up top (usually an error), if passed as an arg
    if [[ ! -z $1 ]]; then
        echo $1
    fi
    echo
    echo "    usage: $0 < -v VCF_FILE > < -f VCF_FILE [-t THRESHOLD] >"
    echo
    echo "   VCF Conversion:"
    echo "   -v     Convert the specified VCF file into the beacon SQLite format"
    echo
    echo "   VCF Filtering:"
    echo "   -f     Filter the VCF file for variants with a minimum number of indications"
    echo "   -t     Minimum threshold when filtering VCF. Default: 5"
    echo
    echo "  Docker functionality:"
    echo "  -r      Run the docker image generated from the repo Dockerfile"
    echo "  -b      Build the docker image generated from the repo Dockerfile"
    echo "    Note: All docker actions can use -d to pass specific docker flags."
    echo
    echo " e.g., to run in docker with a specific sqlite db instead of the current one:"
    echo "     $0 -r -d '-v /some/db.sqlite:/var/www/html/beacon/beacon.GRCh37.sqlite'"
    echo
    exit 1
}

# VCF Filtering defaults
UTIL_DIR=$(abs_dirname)
FILTER_EXE=filter_indb.py
FILTER_OPTS=""

# VCF conversion defaults
BEACON_EXE=${UTIL_DIR%/*}/query
REF=GRCh37
TABLE_NAME=${TABLE_NAME:-OUSAMG}
SQL_FILE="beaconData.$REF.sqlite"

# Docker defaults
DOCKER=$(which docker)
IMAGE_NAME=ousamg/beacon
IMAGE_VER=0.1
CTR_NAME=ous-beacon
SQL_DEST=/var/www/html/beacon/beaconData.GRCh37.sqlite
CONF_DEST=/var/www/html/beacon/beacon.conf

while getopts ":v:f:t:brd:h" opt; do
    case "$opt" in
        v) VCF_FILE="$OPTARG"; ACTION=convert ;;
        f) VCF_FILE="$OPTARG"; ACTION=filter ;;
        t) FILTER_THRESH="$OPTARG" ;;
        b) ACTION=build ;;
        r) ACTION=run ;;
        d) DOCKER_ARGS+=("$OPTARG") ;;
        h) show_help ;;
        :) show_help "Missing argument value: -$OPTARG" ;;
        ?) BADIND=$((OPTIND-1)); show_help "Invalid argument: $(echo ${!BADIND})" ;;
        *) show_help ;;
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
    if [[ ! -z $DEBUG ]]; then
        FILTER_OPTS="$FILTER_OPTS --debug"
    elif [[ ! -z $VERBOSE ]]; then
        FILTER_OPTS="$FILTER_OPTS --verbose"
    fi

    if [[ ! -z $FILTER_THRESH ]]; then
        FILTER_OPTS="$FILTER_OPTS -t $FILTER_THRESH"
    fi

    $UTIL_DIR/$FILTER_EXE -f $VCF_FILE $FILTER_OPTS
elif [[ "$ACTION" == "run" ]]; then
    if [[ $($DOCKER image ls | egrep -c "$IMAGE_NAME\s+$IMAGE_VER") -ne 1 ]]; then
        docker_build
    fi
    docker_run
elif [[ "$ACTION" == "build" ]]; then
    docker_build
else
    echo "Unsupported action somehow: '$ACTION'"
    exit 1
fi
