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
if [[ ! -d $DATA_DIR ]]; then
    mkdir $DATA_DIR
fi

utils/gen_vcf.py -o $DATA_DIR/$TEST_VCF -n 15000 -c 1 --verbose
VERBOSE=1 make filter VCF_FILE=$DATA_DIR/$TEST_VCF BED_FILTER=test/chr1_filter.bed
ORIG_LINES=$(zcat $DATA_DIR/$TEST_VCF | wc -l)
FILT_LINES=$(zcat $FILT_VCF | wc -l)
if [[ -z $FILT_LINES ]]; then
  echo "Failed to find filter file contents"
  exit 1
elif [[ $FILT_LINES -ge $ORIG_LINES ]]; then
  echo "Source line count:   $ORIG_LINES"
  echo "Filtered line count: $FILT_LINES"
  echo "Filtered should be lower :("
  exit 1
else
  echo "Filtered $DATA_DIR/$TEST_VCF from $ORIG_LINES to $FILT_LINES"
fi
rm $FILT_VCF
