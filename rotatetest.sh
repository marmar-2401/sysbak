#!/bin/ksh

# Extract MAX_LOG_SIZE value from sysbakrotate.sh
MAX_LOG_SIZE=$(grep -i 'MAX_LOG_SIZE' /sysbak/sysbakrotate.sh | awk -F= '{ print $2 }' | head -n 1)

# Multiply MAX_LOG_SIZE by 2 and calculate count for dd
TESTSIZE=$((MAX_LOG_SIZE * 2))
COUNT=$((TESTSIZE / 100))

# Create a file with random data, size determined by COUNT
dd if=/dev/urandom of=/var/log/sysbak_log bs=100 count=${COUNT}

# Run sysbakrotate.sh in the background
ksh /sysbak/sysbakrotate.sh &

#This is to ensure the sysbakrotate.sh is rotating the sysbak_log correctly
#
#Last Revision: 01/22/2025
#Version: 1.0
#Created By: Mark Pierce-Zellefrow
