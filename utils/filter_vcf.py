#!/usr/bin/env python
from __future__ import print_function, unicode_literals

import argparse
import datetime
import gzip
import os.path
from pybedtools import BedTool
import re
import sys
import vcf

DEF_THRESH = 5

# Long live the one-liner!
# zcat inDB.vcf.gz | perl -lne 'if (defined $parse) {my $sum = 0;while (/indications_OUS(?:WES|T1)=(\w+:\d+(?:,\w+:\d+)*)/g){map {$sum += (split ":", $_)[1]} (split ",", $1)}if ($sum) {$counts{$sum}++}else{print}}else{$parse++ unless /^#/}}{foreach my $k (sort {$a<=>$b} keys %counts){print "$k\t$counts{$k}"}'


def main():
    start_time = datetime.datetime.now()

    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--file', metavar='VCF_FILE', required=True, help="VCF file to convert")
    parser.add_argument('-t', '--threshold', type=int, default=DEF_THRESH,
                            help="Minimum number of indications to share. Default: {}".format(DEF_THRESH))
    parser.add_argument('-b', '--bed', metavar='BED_FILE', help="Filter variants to regions contained in bed file")
    parser.add_argument('-af', '--allele_frequency', type=float, default=1, help="Filter out variants over the given frequency")
    parser.add_argument('--dry-run', action='store_true', help="Don't write a new output, just run", dest="dry_run")
    parser.add_argument('--meta', action='store_true', help="Print meta info after filtering")
    parser.add_argument('--verbose', action='store_true', help="be extra chatty")
    parser.add_argument('--debug', action='store_true', help="run in debug mode")
    args = parser.parse_args()

    if args.debug:
        setattr(args, 'verbose', True)

    if args.verbose or args.dry_run:
        setattr(args, 'meta', True)


    meta = {"under_threshold": 0, "unique": 0, "seen": 0, "missing_indications": 0, "bed_filtered": 0, "af_filtered": 0}

    if args.bed:
        if args.verbose:
            print("{}\tFiltering regions from {}".format(now(), args.bed))
        input_vcf = BedTool(args.file)
        bed_filter = BedTool(args.bed)
        filtered_vcf = input_vcf.intersect(bed_filter, header = True)
        if len(filtered_vcf) > 0:
            bed_delta = len(input_vcf) - len(filtered_vcf)
            meta["bed_filtered"] = bed_delta

            tmp_fname = "tmp_{}".format(os.path.basename(args.file))
            filtered_vcf.saveas(tmp_fname)
            input_filename = tmp_fname
            in_header = False

            if args.verbose:
                print("{}\tFinished filtering regions from {}".format(now(), args.bed))
        else:
            print("\nWARNING: Zero variants passed the bed overlap filter.\n")
            sys.exit(1)
    else:
        input_filename = args.file
        in_header = True

    # if input_filename[-3:] == ".gz":
    #     infile = gzip.open(input_filename)
    # else:
    #     infile = open(input_filename)

    if not args.dry_run:
        output_filename = "filtered_{}".format(os.path.basename(args.file))
        if output_filename[-3:] != ".gz":
            output_filename += ".gz"
        if os.path.isfile(output_filename):
            print("Found existing output file, aborting: {}".format(output_filename))
            if args.bed:
                print("First stage output still available at {}".format(tmp_fname))
            sys.exit(1)

    re_inds = re.compile('indications_OUS(?:WES|T1)=(\w+:\d+(?:,\w+:\d+)*)')
    if args.verbose:
        print("{}\tBeginning parse of {}".format(now(), input_filename))

    reader = vcf.Reader(filename = input_filename)
    if not args.dry_run:
        writer = vcf.Writer(gzip.open(output_filename, 'wb'), reader)
    for var in reader:
        write_var = True
        meta["seen"] += 1

        if "indications_OUSWES" in var.INFO:
            inds = sum([int(x.split(":")[1]) for x in var.INFO["indications_OUSWES"]])
            if inds < args.threshold:
                write_var = False
                meta["under_threshold"] += 1
                if inds == 1:
                    meta["unique"] += 1
        else:
            meta["missing_indications"] += 1
            inds = -1
            write_var = False

        if "AF_OUSWES" in var.INFO:
            if len(var.INFO["AF_OUSWES"]) > 1:
                meta["af_long"] += 1
            else:
                if var.INFO["AF_OUSWES"][0] > args.allele_frequency:
                    write_var = False
                    meta["af_filtered"] += 1

        if write_var and not args.dry_run:
            writer.write_record(var)

        if args.debug and meta["seen"] >= 100:
            break

    # with gzip.open(output_filename, 'wb') as outfile:
        # for bline in infile:
        #     line = bline.decode("UTF-8")
        #     if not in_header:
        #         meta["seen"] += 1
        #         if args.verbose and meta["seen"] % 100000 == 0:
        #             print("{}\tReading line {}".format(now(), meta["seen"]))
        #
        #         result = re.search(re_inds, line)
        #         if result:
        #             total = 0
        #             labels = []
        #             for res in result.group().split(","):
        #                 lbl, inds = res.split(":")
        #                 total += int(inds)
        #                 labels.append(lbl)
        #             if total < args.threshold:
        #                 meta["under_threshold"] += 1
        #                 if total == 1:
        #                     meta["unique"] += 1
        #                 if args.debug:
        #                     cols = line.split("\t")
        #                     var = "chr{}.{}.{}->{}".format(cols[0], cols[1],cols[3], cols[4])
        #                     print("Variant {} below threshold {} ({}), found groups: {}".format(var, args.threshold, total, result.group()))
        #                 continue
        #         else:
        #             meta["missing_indications"] += 1
        #     else:
        #         if line[:2] != "##":
        #             in_header = False

            # outfile.write(bline)


    # clean up file handles and any temp files created
    # infile.close()
    if args.bed:
        os.unlink(tmp_fname)

    finish_time = datetime.datetime.now()
    run_time = finish_time - start_time

    if args.verbose:
        print("{}\tFinished filtering {}".format(now(), input_filename))

    # bed filtering happens in a previous step, so needs to add those to the other filter steps
    meta["total"] = meta["seen"] + meta["bed_filtered"]
    meta["shareable"] = meta["total"] - meta["bed_filtered"] - meta["af_filtered"] - meta["under_threshold"]
    if meta["missing_indications"] / meta["total"] > 0.1:
        print("\n\n*** WARNING *** Missing indications on {missing_indications} of {total} variants\n".format(**meta))

    if args.meta:
        print()
        print("Processing stats on {}".format(args.file))
        print("\tTotal variants:      {}".format(meta["total"]))
        print("\tTotal shareable:     {} ({:.02f}%)\n".format(meta["shareable"], meta["shareable"] / meta["total"] * 100))

        print("\tBED filtered:        {} ({:.02f}%)\n".format(meta["bed_filtered"], meta["bed_filtered"] / meta["total"] * 100))

        print("\tAF threshold:        {}".format(args.allele_frequency))
        print("\tAF filtered:         {} ({:.02f}%)\n".format(meta["af_filtered"], meta["af_filtered"] / meta["total"] * 100))

        print("\tThreshold minimum:   {}".format(args.threshold))
        print("\tN under threshold:   {} ({:.02f}%)".format(meta["under_threshold"], meta["under_threshold"] / meta["total"] * 100))
        print("\tN unique:            {} ({:.02f}%)".format(meta["unique"], meta["unique"] / meta["total"] * 100))
        print("\tNo indications:      {} ({:.02f}%)".format(meta["missing_indications"], meta["missing_indications"] / meta["total"] * 100))

        print("\tTotal run time:      {:02d}m{:02d}.{:03d}s".format(run_time.seconds // 60, run_time.seconds % 60, run_time.microseconds // 1000))
        print()

def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


###


if __name__ == '__main__':
    main()
