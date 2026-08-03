#!/bin/bash
# Run the build script in WSL
wsl -- bash -c "
export HOME=/home/king
cd /mnt/c/Users/king/Desktop/Hermes/openwrt-ci-roc-master
bash -x ./local_build.sh 2>&1
"
