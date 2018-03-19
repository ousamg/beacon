#!/bin/bash

set -e

if [[ ! -d utils ]]; then
    echo "This must be run from the root repo directory"
    exit 1
fi

DATA_DIR=test_data
TEST_VCF=test.vcf.gz
FILT_VCF=filtered_$TEST_VCF

if [[ -f $FILT_VCF ]]; then
    rm $FILT_VCF
fi
utils/gen_vcf.py -o $DATA_DIR/$TEST_VCF -n 150000 -c 1 --verbose
VERBOSE=1 utils/ous-beacon.sh -f $DATA_DIR/$TEST_VCF -g test/chr1_filter.bed
rm $FILT_VCF
