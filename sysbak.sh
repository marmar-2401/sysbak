#!/bin/ksh

# Variables and Files
DETAILS_FILE="backup_details"
SERIAL_FILE="usb_serial"
USB_DETAILS="usb_details"
SYSBAK_LOG="/var/log/sysbak_log"
CLIENT_RECIPIENT="markp@softcomputer.com"
HOSTNAME=$(uname -n)
TIME=$(date "+%T")
CURRENT_DATE=$(date "+%b%d%Y")
USB_LIST=$(lsdev | grep -i usbms | awk '{print $1}')
USB_COUNT=$(echo "${USB_LIST}" | wc -l)
LAST_SERIAL=$( [ -f "${SERIAL_FILE}" ] && cat "${SERIAL_FILE}" || echo "" )

# Function: Show Help Information
show_help() {
    cat << EOF
###########################################
### Help Section (shown with --help) ######
###########################################
Description:
This script performs a system backup to a USB drive on an AIX host.

Requirements:
-Sendmail must be installed
-3 USBs larger than 10 GB each

Setup:
-Make a sysbak directory for the sysbak.sh script to go into so when it produces its associated files they are together.
-Configure the "CLIENT_RECIPIENT" variable in the top of the script for backup alerting.
-Create a cron job using crontab -e as a root user. 
EX:
* * * * * ksh /path/to/sysbak.sh &

-Put the sysbakrotate.sh into the sysbak directory and set its cronjob.
EX:
* * * * * ksh /path/to/sysbakrotate.sh &


Usage:
  chmod +x sysbak.sh
  ./sysbak.sh
  ./sysbak.sh --help

Override Backing Up To The Same USB:
- '> usb_serial' - Overwrite the stored serial number to be nothing
- 'ksh sysbak.sh' - Runs the sysbak.sh script in the background 

Exit Codes:
1: Sendmail Is Not Installed 
2: USB Device Removal Has Failed 
3: Device Discovery Error 
4: No USB Devices Detected
5: Multiple USB Devices Detected 
6: Failed To Detect USB Serial Number (Unsupported USB)
7: USB Device Is Under 10 GBs
8: Serial Number Conflict USB Was Not Changed Since Last Update 
9: No ROOTVG Detected On Server 
10: Backup Has Failed On A Multiple ROOTVG System 
11: Backup Has Failed On A Single ROOTVG System
13: Failed to create bosboot bootdisk after remirroring
14: Failed bosboot for /dev/ipldevice
15: Failed To Update Normal Bootlist
16: Failed To Update Service
17: Failed savebase after bosboot


Last Revision: 01/21/2025
Version: 1.0
Created By: Mark Pierce-Zellefrow
Email: markp@softcomputer.com
EOF
}

# Check if help is requested
if [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# Redirect all output to the log file
exec >"${DETAILS_FILE}" 2>&1

# Creates the sysbak_log file in /var/log
if [ ! -d "${SYSBAK_LOG}" ]; then
    touch "${SYSBAK_LOG}"
fi


# Step 1: Check if Sendmail is Installed
if ! command -v sendmail >/dev/null 2>&1; then
    echo "Sendmail is not installed. Exiting."
    echo "Sendmail is not installed on ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    echo "Serial:None Exit Code:1 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    exit 1
fi

# Step 2: Handle Previous USB Serial Number
if [ -z "${LAST_SERIAL}" ]; then
    echo "No previous USB serial number found. Creating ${SERIAL_FILE}."
    touch "${SERIAL_FILE}"
else
    echo "Last USB Serial: ${LAST_SERIAL}"
fi

# Step 3: Remove Existing USB Devices
if [ -n "${USB_LIST}" ]; then
    echo "Removing all detected USB devices..."
    for DEVICE in ${USB_LIST}; do
        echo "Removing device: ${DEVICE}"
        if rmdev -dl "${DEVICE}" 2>/dev/null; then
            echo "Successfully removed ${DEVICE}."
        else
            echo "Failed to remove ${DEVICE}."
            echo "Serial:None Exit Code:2 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
            echo "USB Device Removal On ${HOSTNAME} failed. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 2
        fi
    done
else
    echo "No USB devices found to remove."
fi

# Step 4: Rediscover USB Devices
echo "Discovering USB devices..."
cfgmgr -l usb0
if [ $? -ne 0 ]; then
    echo "Device discovery encountered an error."
    echo "Serial:None Exit Code:3 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Device discovery error occurred on ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 3
fi

# Step 5: Check USB Devices
USB_LIST=$(lsdev | grep -i usbms | awk '{print $1}')
USB_COUNT=$(echo "${USB_LIST}" | wc -l)

if [ "${USB_COUNT}" -eq 0 ]; then
    echo "No USB devices detected."
    echo "Serial:None Exit Code:4 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "No USBs connected to ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 4
elif [ "${USB_COUNT}" -gt 1 ]; then
    echo "Multiple USB devices detected."
    lsconf | grep -i 'Serial Number' >> "${USB_DETAILS}"
    for DEVICE in ${USB_LIST}; do
        LOCATION_CODE=$(lscfg -vpl "${DEVICE}" | grep -i "usbms" | awk '{print $2}' | sed -n 's/.*-\([A-Z][0-9]*-[A-Z][0-9]*\)-.*/\1/p')
        echo "Device: ${DEVICE}, Location Code: ${LOCATION_CODE}" >> "${USB_DETAILS}"
    done
    echo "Serial:Multiple Exit Code:5 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    mail -s "${HOSTNAME} Backup Report - Multiple USBs Detected" ${CLIENT_RECIPIENT} < "${USB_DETAILS}"
    rm -f "${USB_DETAILS}"
    exit 5
else
    echo "USB Discovered:${USB_LIST}"
fi

# Step 6: Retrieve USB Serial Number
DEVICE=$(echo "${USB_LIST}" | head -n 1)
if [ -z "${DEVICE}" ]; then
    echo "No valid USB device found after discovery."
    echo "Serial:None Exit Code:4 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "No valid USB device found on ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 4
fi

CURRENT_SERIAL=$(lscfg -vpl "${DEVICE}" | grep -i "Serial Number" | awk -F. '{print $NF}')
if [ -z "${CURRENT_SERIAL}" ]; then
    echo "Failed to retrieve USB serial number."
    echo "Serial:None Exit Code:6 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Unsupported USB Connected To ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 6
fi

# Step 7: Verify USB Device Size
DEVICE_SIZE=$(bootinfo -s ${DEVICE})
if [ -z "${DEVICE_SIZE}" ] || [ "${DEVICE_SIZE}" -lt 10240 ]; then
    echo "USB device size ${DEVICE_SIZE:-0} MB is smaller than 10GB."
    echo "Serial:${CURRENT_SERIAL} Exit Code:7 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Connected USB Is Not Large Enough on ${HOSTNAME} For Backup. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 7
fi

# Step 8: Check Serial Number Change
if [ "${CURRENT_SERIAL}" = "${LAST_SERIAL}" ]; then
    echo "USB Serial Number Conflict."
    echo "Serial:${CURRENT_SERIAL} Exit Code:8 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "USB Was Not Changed On ${HOSTNAME} Since Last Update. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 8
fi

# Step 9: Check If There Is a Solo Rootvg, Mirrored Rootvg, or Spanned Rootvg
ROOTVG_COUNT=$(lspv | grep -iw 'rootvg' | wc -l)

if [ "${ROOTVG_COUNT}" -eq 0 ]; then
    echo "No ROOTVG Detected."
    echo "Serial:${CURRENT_SERIAL} Exit Code:9 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "No ROOTVG detected on ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 9
elif [ "${ROOTVG_COUNT}" -gt 1 ]; then
    echo "Multiple ROOTVGs Detected."
    
    # Extract the logical and physical partition details
LP=$(lsvg -l rootvg | awk 'NR > 2 { print $3; exit 0; }')
PV=$(lsvg -l rootvg | awk 'NR > 2 { print $4; exit 0; }')

# Find the backup disk (assuming it's the first disk not in use by rootvg)
BACKUP_DISK=$(lspv | grep -i rootvg | awk 'NR==1 {print $1}')

# Check if the physical volume is mirrored
if (( ${PV} == 2 * ${LP} )); then
    ROOTVG_STATUS="Mirrored"
    
    # Unmirror the volume group
    unmirrorvg rootvg ${BACKUP_DISK}
    echo "The Volume Group Is Mirrored."
    echo "Starting System Backup To /dev/${DEVICE}..."
    
    # Perform the backup using mksysb
    if ! mksysb -eiXpN /dev/${DEVICE} /dev/${BACKUP_DISK}; then
        echo "Backup Failed."
        echo "Serial:${CURRENT_SERIAL} Exit Code:10 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
        echo "Backup has failed on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
        exit 10
    fi

   # Remirroring the disks
   mirrorvg -S rootvg ${BACKUP_DISK}
   
   # Dynamically find the hdisk names for the rootvg
    ROOTVG_HD_DISK=$(lsvg -p rootvg | awk '{print $1}' | grep -E '^hdisk[0-9]+$')

   # Perform bosboot for the rootvg disks
    for hdisk in ${ROOTVG_HD_DISK}; do
    echo "Running bosboot for /dev/${hdisk}..."
        if ! bosboot -ad /dev/${hdisk}; then
            echo "Error: bosboot failed for /dev/${hdisk}"
            echo "Serial:${CURRENT_SERIAL} Exit Code:13 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Failed to bosboot bootdisk for ${hdisk} on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 13
        fi
    done

    # Perform bosboot for /dev/ipldevice
    echo "Running bosboot for /dev/ipldevice..."
        if ! bosboot -ad /dev/ipldevice; then
            echo "Error: bosboot failed for /dev/ipldevice"
            echo "Serial:${CURRENT_SERIAL} Exit Code:14 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Failed bosboot for /dev/ipldevice on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 14
        fi

    # Update the boot list
    echo "Updating boot list for rootvg disks..."
        if ! bootlist -m normal ${ROOTVG_HD_DISK}; then
            echo "Error: Failed to update the normal boot list."
            echo "Serial:${CURRENT_SERIAL} Exit Code:15 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Failed To Update Normal Bootlist on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 15
        fi

        if ! bootlist -m service cd0 rmt0 ${ROOTVG_HD_DISK}; then
            echo "Error: Failed to update the service boot list."
            echo "Serial:${CURRENT_SERIAL} Exit Code:16 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Failed To Update Service Bootlist on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 16
        fi

    # Save the base system configuration
 
    echo "Saving Base System Configuration..."
        if ! savebase -v; then
            echo "Error: Failed To Save The Base System Configuration."
            echo "Serial:${CURRENT_SERIAL} Exit Code:17 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Failed savebase after bosboot on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 17
        fi    

    fi
    
else
    ROOTVG_STATUS="Single Disk"
    echo "Starting System Backup To /dev/${DEVICE}..."
    
    if ! mksysb -eiXpN /dev/${DEVICE}; then
        echo "Backup Failed."
        echo "Serial:${CURRENT_SERIAL} Exit Code:11 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
        echo "Backup has failed on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
        exit 11
    fi
fi

# Success
echo "Backup Completed Successfully."
echo "${CURRENT_SERIAL}" > "${SERIAL_FILE}"
echo "Serial:${CURRENT_SERIAL} Exit Code:0 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
echo "Backup was successful on ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
exit 0
