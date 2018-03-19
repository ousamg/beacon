#!/usr/bin/env python
from __future__ import print_function, unicode_literals

import argparse
import datetime
import gzip
import random
import sys

# GRCh37 max chrom lengths
CHROMS = [
    ("1", 249250621),
    ("2", 243199373),
    ("3", 198022430),
    ("4", 191154276),
    ("5", 180915260),
    ("6", 171115067),
    ("7", 159138663),
    ("8", 146364022),
    ("9", 141213431),
    ("10", 135534747),
    ("11", 135006516),
    ("12", 133851895),
    ("13", 115169878),
    ("14", 107349540),
    ("15", 102531392),
    ("16", 90354753),
    ("17", 81195210),
    ("18", 78077248),
    ("19", 59128983),
    ("20", 63025520),
    ("21", 48129895),
    ("22", 51304566),
    ("X", 155270560),
    ("Y", 59373566)
]
BASES = [ "A", "C", "G", "T" ]
# weight variant types for random.choice
VAR_TYPES = ["SNP"] * 90 + ["INS"] * 5 + ["DEL"] * 5
MAX_INS = 10
MAX_DEL = 10
VCF_HEADER = b"""
##fileformat=VCFv4.1
##source=SelectVariants
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
##reference=GRCh37
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DUMMY
""".strip()
QUAL_MIN = 10
QUAL_MAX = 500
IND_LABELS = 15
IND_MAX = 350
IND_PREFIX = "indications_OUSWES"
DEFAULT_VAL = '.'
DEFAULT_NUM = 500
DEFAULT_OUTPUT = "ousamg-test_data.vcf.gz"
DEFAULT_CHROM = [ x[0] for x in CHROMS ]
FILTERS = ["PASS"] * 3 + ["LowQual"]
FORMAT = 'GT'
DUMMY = './.'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--chrom', type=comma_list, default=DEFAULT_CHROM, help='Comma delimited string of chromosomes to use. Default: {}'.format(','.join(DEFAULT_CHROM)))
    parser.add_argument('-n', '--num', type=int, default=DEFAULT_NUM, help='Number of variants per chromosome to generate. Default: {}'.format(DEFAULT_NUM))
    parser.add_argument('-o', '--output', default=DEFAULT_OUTPUT, help="output filename. Default: {}".format(DEFAULT_OUTPUT))
    parser.add_argument('--verbose', action='store_true', help="be extra chatty")
    parser.add_argument('--debug', action='store_true', help="run in debug mode")
    args = parser.parse_args()

    if args.debug:
        setattr(args, 'verbose', True)

    if len(args.output) < 3 or args.output[-3:] != '.gz':
        output_filename = "{}.gz".format(args.output)
    else:
        output_filename = args.output

    if args.verbose:
        print("{}\tWriting {} fake variants for chromosomes {} to {}".format(now(), args.num, ', '.join(args.chrom), output_filename))

    with gzip.open(output_filename, "wb") as output:
        output.write(VCF_HEADER + b"\n")
        for chrom_info in CHROMS:
            chrom, chrom_max = chrom_info
            if chrom not in args.chrom:
                continue

            if args.verbose:
                print("{}\tGenerating {} variants on chromosome {}".format(now(), args.num, chrom))

            for var_num in range(args.num):
                row = {
                    "CHROM": chrom,
                    "FORMAT": FORMAT,
                    "DUMMY": DUMMY
                }

                # pos between 1 and end of chromosome
                row["POS"] = random.randint(1, chrom_max)

                # ID is ignored, so just use .
                row["ID"] = '.'

                # set up the ref / alt alleles
                vtype = random.choice(VAR_TYPES)
                row["REF"] = random.choice(BASES)
                if vtype == "SNP":
                    row["ALT"] = random.choice(list(filter(lambda x: x != row["REF"], BASES)))
                elif vtype == "INS":
                    row["ALT"] = row["REF"]
                    for ibase in range(random.randint(1, MAX_INS)):
                        row["ALT"] += random.choice(BASES)
                elif vtype == "DEL":
                    row["ALT"] = row["REF"]
                    for dbase in range(random.randint(1, MAX_DEL)):
                        row["REF"] += random.choice(BASES)

                # qual as random float
                row["QUAL"] = QUAL_MIN + random.random() * QUAL_MAX

                # random filter selection, just for the sake of variety
                row["FILTER"] = random.choice(FILTERS)

                # set up indications from estimated distributions
                inds = {}
                ind_roll = random.random() * 100
                if ind_roll < 60:
                    num_inds = 1
                elif ind_roll < 68.5:
                    num_inds = 2
                elif ind_roll < 72:
                    num_inds = 3
                elif ind_roll < 75.5:
                    num_inds = 4
                elif ind_roll < 77:
                    num_inds = 5
                elif ind_roll < 78.5:
                    num_inds = 6
                elif ind_roll <= 80:
                    num_inds = 7
                else:
                    num_inds = random.randint(8, 200)

                if args.debug:
                    print("{}\tGot ind_roll {} -> {} for var #{} on {}".format(now(), ind_roll, num_inds, var_num, chrom))
                while num_inds > 0:
                    gp_cnt = random.randint(1, num_inds)
                    num_inds -= gp_cnt
                    gp_name = "Label{}".format(random.randint(1, IND_LABELS))
                    while gp_name in inds.keys():
                        gp_name = "Label{}".format(random.randint(1, IND_LABELS))
                    inds[gp_name] = gp_cnt
                total_inds = sum(inds.values())
                ind_str = ','.join(["{}:{}".format(k, v) for k, v in inds.items()])

                # add some noise to the full info string
                hom = random.randint(0, total_inds)
                het = total_inds - hom
                row["INFO"] = ";".join([
                    "filter_OUSWES={}".format(row["FILTER"]),
                    "{}={}".format(IND_PREFIX, ind_str),
                    "Hom_OUSWES={}".format(hom),
                    "Het_OUSWES={}".format(het),
                    "AN_OUSWES={}".format(hom + 2 * het)
                ])

                row_str = "{CHROM}\t{POS}\t{ID}\t{REF}\t{ALT}\t{QUAL:.02f}\t{FILTER}\t{INFO}\t{FORMAT}\t{DUMMY}\n".format(**row)
                if sys.version_info.major == 3:
                    row_str = row_str.encode('utf-8')
                output.write(row_str)

                if args.debug and var_num >= 10:
                    break

    if args.verbose:
        print("{}\tFinished writing all variants to {}".format(now(), output_filename))


###

def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def comma_list(arg_str):
    try:
        arg_list = arg_str.split(',')
    except Exception as e:
        raise argparse.ArgumentTypeError(str(e))

    return arg_list


if __name__ == '__main__':
    main()
