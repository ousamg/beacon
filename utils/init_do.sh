#!/bin/bash

while sudo fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
   sleep 1
done

apt-get install make -y
cd beacon
make deploy
