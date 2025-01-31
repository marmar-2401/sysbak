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

# Function To Show Help Information
show_help() {
    cat << EOF
###########################################
### Help Section (shown with --help) ######
###########################################
Description:
This Script Performs A System Backup To A USB Device On A AIX host.

Usage:
  chmod +x sysbak.sh
  ./sysbak.sh
  ./sysbak.sh --help

Exit Codes:
1: Sendmail Is Not Installed 
2: USB Device Removal Has Failed 
3: Device Discovery Error 
4: No USB Devices Detected
5: Multiple USB Devices Detected 
6: Failed To Detect USB Serial Number (Unsupported USB)
7: USB Device Is Under 10 GBs
8: Serial Number Conflict USB Was Not Changed Since Last Update 
9: Backup Has Failed On A Multiple ROOTVG System 
10: Backup Has Failed On A Single ROOTVG System
11: Failed To Create Custom /image.data
12: Custom /image.data File Could Not Be Found 

Last Revision: 01/21/2025
Version: 1.0
Created By: Mark Pierce-Zellefrow
Email: markp@softcomputer.com
EOF
}

# Check If Help Is Requested
if [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# Redirect All Output To The backup_details File 
exec >"${DETAILS_FILE}" 2>&1

# Creates The sysbak_log File In /var/log
if [ ! -d "${SYSBAK_LOG}" ]; then
    touch "${SYSBAK_LOG}"
fi

# Check If Sendmail Is Installed
if ! command -v sendmail >/dev/null 2>&1; then
    echo "Sendmail Is Not Installed. Exiting."
    echo "Sendmail Is Not Installed On ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    echo "Serial:None Exit Code:1 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    exit 1
fi

# Handles Previous USB Serial Number
if [ -z "${LAST_SERIAL}" ]; then
    echo "No Previous USB Serial Number Found. Creating ${SERIAL_FILE}."
    touch "${SERIAL_FILE}"
else
    echo "Last USB Serial: ${LAST_SERIAL}"
fi

# Removes Existing USB Devices
if [ -n "${USB_LIST}" ]; then
    echo "Removing All Detected USB Devices..."
    for DEVICE in ${USB_LIST}; do
        echo "Removing Device: ${DEVICE}"
        if rmdev -dl "${DEVICE}" 2>/dev/null; then
            echo "Successfully Removed ${DEVICE}."
        else
            echo "Failed To Remove ${DEVICE}."
            echo "Serial:None Exit Code:2 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
            echo "USB Device Removal On ${HOSTNAME} failed. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 2
        fi
    done
else
    echo "No USB Devices Found To Remove."
fi

# Rediscover USB Devices
echo "Discovering USB Devices..."
cfgmgr -l usb0
if [ $? -ne 0 ]; then
    echo "Device Discovery Encountered An Error."
    echo "Serial:None Exit Code:3 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Device Discovery Error Occurred On ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 3
fi

# Check For Names Of USB Devices
USB_LIST=$(lsdev | grep -i usbms | awk '{print $1}')
USB_COUNT=$(echo "${USB_LIST}" | wc -l)

if [ "${USB_COUNT}" -eq 0 ]; then
    echo "No USB Devices Detected."
    echo "Serial:None Exit Code:4 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "No USBs Connected To ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 4
elif [ "${USB_COUNT}" -gt 1 ]; then
    echo "Multiple USB Devices Detected."
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

# Retrieval Of USB Serial Number
DEVICE=$(echo "${USB_LIST}" | head -n 1)
CURRENT_SERIAL=$(lscfg -vpl "${DEVICE}" | grep -i "Serial Number" | awk -F. '{print $NF}')

if [ -z "${CURRENT_SERIAL}" ]; then
    echo "Failed To Retrieve USB Serial Number."
    echo "Serial:None Exit Code:6 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Unsupported USB Connected To ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 6
fi

# Verification Of USB Device Size
DEVICE_SIZE=$(bootinfo -s ${DEVICE})
if [ -z "${DEVICE_SIZE}" ] || [ "${DEVICE_SIZE}" -lt 10240 ]; then
    echo "USB Device Size ${DEVICE_SIZE:-0} MB Is Smaller Than 10GB."
    echo "Serial:${CURRENT_SERIAL} Exit Code:7 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Connected USB Is Not Large Enough on ${HOSTNAME} For Backup. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 7
fi

# Check If Serial Number Changed Ensures USB Was Changed 
if [ "${CURRENT_SERIAL}" = "${LAST_SERIAL}" ]; then
    echo "USB Serial Number Conflict."
    echo "Serial:${CURRENT_SERIAL} Exit Code:8 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "USB Was Not Changed On ${HOSTNAME} Since Last Update. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 8
fi

# Check If There Is a Single Disk Rootvg Or A Mirrored Rootvg 
ROOTVG_COUNT=$(lspv | grep -iw 'rootvg' | wc -l)

if [ "${ROOTVG_COUNT}" -gt 1 ]; then    
    # Extracts The Logical and Physical Partition Details Of Rootvg 
    LP=$(lsvg -l rootvg | awk 'NR > 2 { print $3; exit 0; }')
    PV=$(lsvg -l rootvg | awk 'NR > 2 { print $4; exit 0; }')

    # Checks If The Rootvg Is Mirrored 
    if (( ${PV} == 2 * ${LP} )); then
        ROOTVG_STATUS="Mirrored"
        echo "The Volume Group Is Mirrored"

# Create The Custom image.data File Using mkszfile
echo "Creating image.data Using mkszfile..."
mkszfile

# Check If mkszfile Was Successful
if [ $? -ne 0 ]; then
    echo "Failed to create /image.data."
    echo "Serial:${CURRENT_SERIAL} Exit Code:11 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "Failed To Create Custom /image.data File on ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}  
    exit 12 
fi

# Get The Source Disk For The mksysb Backup To Store In The image.data File 
SOURCE_DISK=$(lspv | grep -i rootvg | awk '{ print $1 }' | head -n 1)

# Specifies The Path To The image.data File
IMAGE_DATA_FILE="/image.data"
TMP_FILE="/imagedata.tmp"

# Preserve formatting and update LV_SOURCE_DISK_LIST
awk -v disk="$SOURCE_DISK" '{
    if ($1 == "LV_SOURCE_DISK_LIST=") {
        print $1, disk;
    } else {
        print $0;
    }
}' "$IMAGE_DATA_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$IMAGE_DATA_FILE"

COPIESFLAG=0  # Initialize flag

# Preserve indentation while modifying COPIES and PP values
awk '{
    if ($1 == "COPIES=" && $2 == "2") {
        print $1, "1";
        COPIESFLAG=1;
    } else if (COPIESFLAG && $1 == "PP=") {
        print $1, int($2 / 2);
        COPIESFLAG=0;
    } else {
        print $0;
    }
}' "$IMAGE_DATA_FILE" > "$TMP_FILE"

# Replace the original file after processing
mv "$TMP_FILE" "$IMAGE_DATA_FILE"

echo "The Custom /image.data Was Successfully Created To Break The Mirror In The Backup"
echo "Starting System Backup To /dev/${DEVICE}..."

    if [ $MKSYSB_EXIT_CODE -ne 0 ]; then
        echo "Backup Failed. Exit Code: $MKSYSB_EXIT_CODE"
        echo "Serial:${CURRENT_SERIAL} Exit Code:$MKSYSB_EXIT_CODE Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
        echo "Backup Has Failed On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
        exit 10  # Exit the script with a custom exit code (10)
    fi

else
    ROOTVG_STATUS="Single Disk"
    echo "Starting System Backup To /dev/${DEVICE}..."
    
    if ! mksysb -eXpi /dev/${DEVICE}; then
        echo "Backup Failed."
        echo "Serial:${CURRENT_SERIAL} Exit Code:10 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
        echo "Backup Has Failed On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
        exit 11
    fi
fi

# Backup Was Successfully Completed
echo "Backup Completed Successfully."
echo "${CURRENT_SERIAL}" > "${SERIAL_FILE}"
echo "Serial:${CURRENT_SERIAL} Exit Code:0 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
echo "Backup Was Successful On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
exit 0
