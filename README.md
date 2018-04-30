Introduction
============

The [GA4H beacon system](http://beacon-project.io) is a means of more
easily sharing genetic data. The user specifies a chromosome, position and allele
and the beacon network returns true if anyone is sharing a dataset with that
variant. They can then contact the dataset owner for additional details and
sharing requirements.

The OUSAMG beacon is a python implementation of the 0.2 API, based originally on
the [UCSC Beacon](https://github.com/maximilianh/ucscBeacon). The data we share
is from our internal database, filtered for gene regions of interest that have
5 or more observations within our database. This minimizes the likelihood of
sample re-identification. VCF data is not stored on the web server, just the
chromosome-position-allele combinations that we have decided to share.

Additional information on the Beacon Network:
* FAQ page - http://beacon-project.io/faqs.html
* Full API spec
    * 0.4: https://app.swaggerhub.com/apis/ELIXIR-Finland/ga-4_gh_beacon_api_specification/0.4.0 (interactive)
    * 0.4: https://github.com/ga4gh-beacon/specification/releases/tag/v0.4.0 (archive)
    * 0.3: https://github.com/ga4gh-beacon/specification/releases/tag/v0.3.0 (archive)
* Central beacon search page - https://beacon-network.org/#/search


Quick-start using the built-in webserver
=======================================

This should work in OSX, Linux or Windows when Python is installed (in Windows
you need to rename query to query.py):

From the repo base directory:

    $ ./query -p 8888

Then go to your web browser and try a few URLs:

* http://localhost:8888/info
* http://localhost:8888/query?dataset=test&chromosome=1&position=10150&alternateBases=A
* http://localhost:8888/query?dataset=test&chromosome=1&position=10150&alternateBases=C

Stop the beacon server by hitting Ctrl+C.

Reset the databse and import your own data, without filtering:

    $ mv beaconData.GRCh37.sqlite beaconData.GRCh37.sqlite.old
    $ ./query GRCh37 datasetName yourData.vcf.gz

Details on importing other data formats are below, and details on filtering your data
can be found by running `make help` in the base repo directory.

Restart the server:

    $ ./query -p 8888

And query again with URLs, as above, but adapting the chromosome and position to one
that is valid in your dataset.

You can adapt the name of your beacon, your institution etc. by editing the
file beacon.conf and change the beacon help text by editing the file help.txt

Running in Docker
=================

From the repo base directory:

    $ make deploy


Test it
=======

Usage help info:

    $ curl http://localhost/query


Some test queries against the ICGC sample that is part of the repo:

    $ curl 'http://localhost/query?chromosome=1&position=10150&alternateBases=A'
    $ curl 'http://localhost/query?chromosome=10&position=4772339&alternateBases=T'

**NB:** Position is _0-indexed_ and not 1-indexed as in a VCF file

View the meta information about the beacon (stored in `config/beacon.conf`):

    $ curl http://localhost/info


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

    $ curl "http://localhost/query?chromosome=1&position=1234&alternateBases=T"

By default, the beacon will check all datasets, unless you provide a dataset name, like this:

    $ curl "http://localhost/query?chromosome=1&position=1234&alternateBases=T&dataset=icgc"

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
