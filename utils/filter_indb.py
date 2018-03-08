#!/usr/bin/env python3
import argparse
import datetime
import gzip
import os.path
import re
import sys

DEF_THRESH = 5

# Long live the one-liner!
# zcat inDB.vcf.gz | perl -lne 'if (defined $parse) {my $sum = 0;while (/indications_OUS(?:WES|T1)=(\w+:\d+(?:,\w+:\d+)*)/g){map {$sum += (split ":", $_)[1]} (split ",", $1)}if ($sum) {$counts{$sum}++}else{print}}else{$parse++ unless /^#/}}{foreach my $k (sort {$a<=>$b} keys %counts){print "$k\t$counts{$k}"}'

def main():
    start_time = datetime.datetime.now()

    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--file', metavar='VCF_FILE', required=True, help="VCF file to convert")
    parser.add_argument('-t', '--threshold', type=int, default=DEF_THRESH,
        help="Minimum number of indications to share. Default: {}".format(DEF_THRESH))
    parser.add_argument('--meta', action='store_true', help="Print meta info after filtering")
    parser.add_argument('--verbose', action='store_true', help="be extra chatty")
    parser.add_argument('--debug', action='store_true', help="run in debug mode")
    args = parser.parse_args()

    if args.debug:
        setattr(args, 'verbose', True)

    if args.verbose:
        setattr(args, 'meta', True)

    if args.file[-3:] == ".gz":
        infile = gzip.open(args.file)
    else:
        infile = open(args.file)

    output_filename = "filtered_{}".format(os.path.basename(args.file))
    if output_filename[-3:] != ".gz":
        output_filename += ".gz"
    if os.path.isfile(output_filename):
        print("Found existing output file, aborting: {}".format(output_filename))
        sys.exit(1)

    meta = {"under_threshold": 0, "unique": 0, "total": 0, "missing_indications": 0}
    re_inds = re.compile('indications_OUS(?:WES|T1)=(\w+:\d+(?:,\w+:\d+)*)')
    in_header = True

    if args.verbose:
        print("{}\tBeginning parse of {}".format(now(), args.file))
    with gzip.open(output_filename, 'wb') as outfile:
        for bline in infile:
            line = bline.decode("UTF-8")
            if not in_header:
                meta["total"] += 1
                if args.verbose and meta["total"] % 100000 == 0:
                    print("{}\tReading line {}".format(now(), meta["total"]))

                result = re.search(re_inds, line)
                if result:
                    total = 0
                    labels = []
                    for res in result.group().split(","):
                        lbl, inds = res.split(":")
                        total += int(inds)
                        labels.append(lbl)
                    if total < args.threshold:
                        meta["under_threshold"] += 1
                        if total == 1:
                            meta["unique"] += 1
                        if args.debug:
                            cols = line.split("\t")
                            var = "chr{}.{}.{}->{}".format(cols[0], cols[1],cols[3], cols[4])
                            print("Variant {} below threshold {} ({}), found groups: {}".format(var, args.threshold, total, result.group()))
                        continue
                else:
                    meta["missing_indications"] += 1
            else:
                if line[:2] != "##":
                    in_header = False

            outfile.write(bline)

            if args.debug and meta["total"] >= 100:
                break

    finish_time = datetime.datetime.now()
    run_time = finish_time - start_time

    if args.verbose:
        print("{}\tFinished filtering {}".format(now(), args.file))

    if args.meta:
        print()
        print("Processing stats on {}".format(args.file))
        print("\tTotal lines:         {}".format(meta["total"]))
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
