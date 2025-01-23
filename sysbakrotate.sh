#!/bin/ksh

# Variables
LOG_FILE="/var/log/sysbak_log" # This is from sysbak.sh
ARCHIVE_DIR="/var/log/sysbak_log.archive"
MAX_LOG_SIZE=10485760  
DATE=$(date "+%b%d%Y")
TIME=$(date "+%T")

# Function to display help
show_help() {
    cat << EOF
Usage:
This script should be in the same directory as sysbak.sh and is ideally ran as a cronjob.

EX:
* * * * * ksh /path/to/sysbakrotate.sh &

This script performs log rotation for the specified log file. If the log file 
exceeds the maximum size of 10 MB, it is archived in the specified directory, 
and a new log file is created.

Options:
  --help      Show this help message and exit

Variables:
  LOG_FILE         The log file to monitor (default: sysbak_log)
  ARCHIVE_DIR      The directory where archived logs are stored (default: sysbaklog_archive)
  MAX_LOG_SIZE     The maximum size of the log file in bytes before rotation occurs (default: 10485760 in bytes)

To Run The Script Manually:
  ksh sysbakrotate.sh & 
    
Last Revision: 01/22/2025
Version: 1.0
Created By: Mark Pierce-Zellefrow
Email: markp@softcomputer.com

EOF
}

# Check if --help is requested
if [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# Ensure the archive directory exists
if [ ! -d "${ARCHIVE_DIR}" ]; then
    mkdir -p "${ARCHIVE_DIR}"
fi

# Check if the log file exists and exceeds the size limit
if [ -f "${LOG_FILE}" ]; then
    FILE_SIZE=$(ls -l "${LOG_FILE}" | awk '{ print $5 }')
    if [ "${FILE_SIZE}" -gt "${MAX_LOG_SIZE}" ]; then
        # Extract the base name of the log file (e.g., sysbak_log)
        BASENAME=$(basename "${LOG_FILE}")

        # Archive the current log
        mv "${LOG_FILE}" "${ARCHIVE_DIR}/${BASENAME}_${DATE}.log"
        
        # Create a new empty log file
        touch "${LOG_FILE}"
        echo "Log rotated: ${DATE} ${TIME}" >> "${LOG_FILE}"
    else
        echo "sysbak_log Is Within Size Quota. No Rotation Needed. ${DATE} ${TIME}" >> "${LOG_FILE}"
    fi
else
    echo "Log file does not exist: ${DATE} ${TIME}" >> "${LOG_FILE}"
    exit 1
fi

