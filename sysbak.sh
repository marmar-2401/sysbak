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
9: No ROOTVG Detected On Server 
10: Backup Has Failed On A Multiple ROOTVG System 
11: Backup Has Failed On A Single ROOTVG System
12: Failed To Create Custom /image.data
13: Custom /image.data File Could Not Be Found 

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

if [ "${ROOTVG_COUNT}" -eq 0 ]; then
    echo "No ROOTVG Detected."
    echo "Serial:${CURRENT_SERIAL} Exit Code:9 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
    echo "No ROOTVG detected on ${HOSTNAME}. Backup will not occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
    exit 9
elif [ "${ROOTVG_COUNT}" -gt 1 ]; then
    echo "Multiple ROOTVGs Detected."
    
    # Extracts The Logical and Physical Partition Details Or Rootvg 
    LP=$(lsvg -l rootvg | awk 'NR > 2 { print $3; exit 0; }')
    PV=$(lsvg -l rootvg | awk 'NR > 2 { print $4; exit 0; }')

    # Checks If The Rootvg Is Mirrored 
    if (( ${PV} == 2 * ${LP} )); then
        ROOTVG_STATUS="Mirrored"
    
    echo "The Volume Group Is Mirrored."
    echo "Starting System Backup To /dev/${DEVICE}..."
  
    # Create The Custom image.data File Using mkszfile
    echo "Creating image.data Using mkszfile..."
    mkszfile 

    # Check If mkszfile Was Successful
    if [ $? -ne 0 ]; then
        echo "Failed to create /image.data."
        echo "Serial:${CURRENT_SERIAL} Exit Code:12 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
        echo "Failed To Create Custom /image.data File on ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}  
        exit 12 
    fi

    # Get The Source Disk For The mksysb Backup To Store In The image.data File 
    SOURCE_DISK=$(lspv | grep -i rootvg | awk '{ print $1 }' | head -n 1)

    # Specifies The Path To The image.data File
    IMAGE_DATA_FILE="/image.data"

    # Checks If The image.data File Exists
    if [ ! -f "${IMAGE_DATA_FILE}" ]; then
        echo "${IMAGE_DATA_FILE} Not Found."
        echo "Serial:${CURRENT_SERIAL} Exit Code:13 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
        echo "/image.data File Does Not Exist On ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}  
        exit 13
    fi

    # Divide PPs By 2 For Any data_vg With COPIES= 2
    echo "Dividing PPs by 2 for data_vg with COPIES=2..."
    awk '
    /COPIES= 2/ { 
        copies_two = 1 
    } 
    /COPIES=/ && $0 !~ /COPIES= 2/ { 
        copies_two = 0 
    } 
    /^[ \t]*PP=/ && copies_two { 
        # Match PP= lines, even with leading spaces
        split($0, arr, "=") 
        new_value = int(arr[2] / 2)  # Divide the value of PP by 2
        $0 = arr[1] "=" new_value   # Reconstruct the PP line with the new value
    } 
    { 
        print 
    }' "${IMAGE_DATA_FILE}" > "/temp.data" && mv "/temp.data" "${IMAGE_DATA_FILE}"

    # Change COPIES=2 to COPIES=1
    echo "Updating COPIES=2 to COPIES=1..."
    sed 's/COPIES=[ \t]*2/COPIES=1/g' "${IMAGE_DATA_FILE}" > "/temp.data" && mv "/temp.data" "${IMAGE_DATA_FILE}"

    # Update the LV_SOURCE_DISK_LIST With The New Source Disk
    echo "Updating LV_SOURCE_DISK_LIST To ${SOURCE_DISK}..."
    sed "s/LV_SOURCE_DISK_LIST=.*/LV_SOURCE_DISK_LIST=${SOURCE_DISK}/" "${IMAGE_DATA_FILE}" > "${IMAGE_DATA_FILE}.tmp"
    mv "${IMAGE_DATA_FILE}.tmp" "${IMAGE_DATA_FILE}"
    
    # Confirm The Changes To image.data 
    echo "image.data Has Been Created And Updated Successfully."

    # Perform The Backup Using mksysb
    if ! mksysb -eXpN /dev/${DEVICE} /dev/${BACKUP_DISK}; then
        echo "Backup Failed."
        echo "Serial:${CURRENT_SERIAL} Exit Code:10 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
        echo "Backup Has Failed On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
        exit 10
    fi
    

    rm -rf /image.data 
    echo "Resetting image.data File For Next Update" 

    fi
    
else
    ROOTVG_STATUS="Single Disk"
    echo "Starting System Backup To /dev/${DEVICE}..."
    
    if ! mksysb -eiXpN /dev/${DEVICE}; then
        echo "Backup Failed."
        echo "Serial:${CURRENT_SERIAL} Exit Code:11 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
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
