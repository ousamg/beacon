Originally forked from https://github.com/maximilianh/ucscBeacon

---

Introduction
============

The GA4H beacon system http://ga4gh.org/#/beacon is a small webservice
that accepts a chromosome position and allele and replies with "true" or
"false. This is an implementation of the GA4GH beacon 0.2 draft API which
tries to be as simple as possible to install and configure, it requires
only Python >2.5, the default in current linux distributions and OSX.

For security reasons, the script is small and either
provides its own webserver or runs within your existing webserver as a CGI.
This beacon can slow down queries if too many come in from the same IP
address, to prevent that someone queries the whole genome (see the end of
this document). For security reasons, your raw data, like VCF (see below) are
not accessed by the script, but first converted into the minimal format
chrom-position-alternateBases.

Quick-start using the built-in webserver
=======================================

This should work in OSX, Linux or Windows when Python is installed (in Windows you need to rename query to query.py):

    $ git clone https://git@git.ousamg.io:apps/beacon.git
    $ cd beacon
    $ ./query -p 8888

Then go to your web browser and try a few URLs:

* http://localhost:8888/info
* http://localhost:8888/query?dataset=test&chromosome=1&position=10150&allele=A&format=text
* http://localhost:8888/query?dataset=test&chromosome=1&position=10150&allele=A
* http://localhost:8888/query?dataset=test&chromosome=1&position=10150&allele=C

Stop the beacon server by hitting Ctrl+C.

Reset the databse and import your own data in VCF format (see below for other supported formats):

    $ rm beaconData.GRCh37.sqlite
    $ ./query GRCh37 datasetName yourData.vcf.gz

Restart the server:

    $ ./query -p 8888

And query again with URLs, as above, but adapting the chromosome and position to one that is valid in your dataset.

You can adapt the name of your beacon, your institution etc. by editing the
file beacon.conf and change the beacon help text by editing the file help.txt

Running in Docker
=================

From the repo base directory:

    $ docker build -t ousamg/beacon .
    $ docker run -p 8080:80 -dit --name ous-beacon ousamg/beacon


Test it
=======

Usage help info:

    $ curl http://localhost:8080/beacon/query

Some test queries against the ICGC sample that is part of the repo:

    $ curl 'http://localhost:8080/beacon/query?chromosome=1&position=10150&alternateBases=A&format=text'
    $ curl 'http://localhost:8080/beacon/query?chromosome=10&position=4772339&alternateBases=T&format=text'

Both should display "true".

Or see the full JSON response:

    $ curl 'http://localhost:8080/beacon/query?chromosome=1&position=10150&alternateBases=A'
    $ curl 'http://localhost:8080/beacon/query?chromosome=10&position=4772339&alternateBases=T'

View the meta information about the beacon (stored in `config/beacon.conf`):

    $ curl http://localhost:8080/beacon/info

For easier usage, the script supports a parameter 'format=text' which prints only one word (true or false). If you don't specify it, the result will be returned as a JSON string, which includes the query parameters:

    $ curl 'http://localhost:8080/beacon/query?chromosome=10&position=9775129&alternateBases=T'


Adding your own data
====================

Remove the default test database:

    $ mv beaconData.GRCh37.sqlite beaconData.GRCh37.sqlite.old

Import some of the provided test files in complete genomics format:

    $ ./query GRCh37 testDataCga test/var-GS000015188-ASM.tsv test/var-GS000015188-ASM2.tsv -f cga

Or import some of the provided test files in complete genomics format:

    $ ./query GRCh37 testDataVcf test/icgcTest.vcf test/icgcTest2.vcf

Or import your own VCF file as a dataset 'icgc':

    $ ./query GRCh37 icgc simple_somatic_mutation.aggregated.vcf.gz

You can specify multiple filenames, so the data will get merged.
A typical import speed is 100k rows/sec, so it can take a while if you have millions of variants.

You should now be able to query your new dataset with URLs like this:

    $ curl "http://localhost:8080/beacon/query?chromosome=1&position=1234&alternateBases=T"

By default, the beacon will check all datasets, unless you provide a dataset name, like this:

    $ curl "http://localhost:8080/beacon/query?chromosome=1&position=1234&alternateBases=T&dataset=icgc"

Note that external beacon users cannot query the database during the import.

Apart from VCF, the program can also parse the complete genomics variants format, BED format of LOVD
and a special format for the database HGMD. You can run the 'query' script from the command line for a list of the import options.


The `utils/` directory
====================

The binary "bottleneck" tool in this directory is a static 64bit file distributed
by UCSC.

It can be downloaded for other platforms from
http://hgdownload.cse.ucsc.edu/admin/exe/ or compiled from source, see
http://genome.ucsc.edu/admin/git.html .

This is also where the [ous-beacon.sh](utils/ous-beacon.sh) script lives, which can
simplify importing data. The goal is to have it also manage the pre-filtering of the VCF
and docker images / containers.

IP throttling
=============

The beacon can optionally slow down requests, if too many come in from the same
IP address. This is meant to prevent whole-genome queries for all alleles. You
have to run a bottleneck server for this, the tool is called "bottleneck".
You can find a copy in the utils/ directory,
or can download it as a binary from http://hgdownload.cse.ucsc.edu/admin/exe/ or
in source from http://genome.ucsc.edu/admin/git.html. Run it as "bottleneck
start", the program will stay as a daemon in the background.

Create a file hg.conf in the same directory as hgBeacon and add these lines:

    bottleneck.host=localhost
    bottleneck.port=17776

For each request, hgBeacon will contact the bottleneck server. It will
increase a counter by 150msec for each request from an IP. After every second
without a request from an IP, 10msec will get deducted from the counter. As
soon as the total counter exceeds 10 seconds for an IP, all beacon replies
will get delayed by the current counter for this IP. If the counter still
exceeds 20 seconds (which can only happen if the client uses multiple
threads), the beacon will block this IP address until the counter falls below
20 seconds again.
