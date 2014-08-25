#!/bin/sh

sysbench --test=fileio --file-num=512 --file-total-size=5G \
         --file-test-mode=seqrd --num-threads=512 --file-block-size=16384 \
         --max-requests=100000 --file-io-mode=sync run
