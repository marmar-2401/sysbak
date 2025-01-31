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
This Script Performs A System Backup To A USB Device On An AIX host.

Usage:
  chmod +x sysbak.sh
  ./sysbak.sh
  ./sysbak.sh --help
  ksh sysbak.sh
  ksh sysbak.sh --help
  
Exit Codes:
1: Sendmail Is Not Installed
2: USB Device Removal Has Failed
3: Device Discovery Error
4: No USB Devices Detected
5: Multiple USB Devices Detected
6: Failed To Detect USB Serial Number (Unsupported USB)
7: USB Device Is Under 10 GBs
8: Serial Number Conflict USB Was Not Changed Since Last Update
9: Backup Has Failed On A Mirrored ROOTVG System
10: Backup Has Failed On A Non-Mirrored ROOTVG System
11: mkszfile Had An Error
12: ROOTVGs Are Spanned 


Last Revision: 01/30/2025
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

#Determines What To Do Dependent On The Number Of USBs In The System
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
    echo "USB Discovered: ${USB_LIST}"
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
    LP=$(lsvg -l rootvg | awk 'NR > 2 { print $3; exit 0; }')
    PV=$(lsvg -l rootvg | awk 'NR > 2 { print $4; exit 0; }')

    # Checks If The Rootvg Is Mirrored Or Spanned 
    if (( ${PV} == 2 * ${LP} )); then
        ROOTVG_STATUS="Mirrored ROOTVG"
        echo "The Volume Group Is Mirrored"
    else
        ROOTVG_STATUS="Spanned"
         echo "ROOTVGs Are"
         echo "Serial:${CURRENT_SERIAL} Exit Code:12 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
         echo "ROOTVGs Are Spanned Backup Will Not Occur ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}  
         exit 12
    fi
        # Create The Custom image.data File Using mkszfile
        echo "Creating Custom image.data File Breaking The Mirror On The System Backup Being Created..."
        mkszfile

        #If mkszfile Exits With Anything Other Than Zero An Error Has Occured 
        if [ $? -ne 0 ]; then
            echo "mkszfile Has An Error That Occured"
            echo "Serial:${CURRENT_SERIAL} Exit Code:11 Date:${CURRENT_DATE} Time:${TIME}" >> "${SYSBAK_LOG}"
            echo "mkszfile Has Had An Error Occur On ${HOSTNAME}. Backup Will Not Occur." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}  
            exit 11 
        fi

        # Get The Source Disk For The mksysb Backup To Store In The image.data File
        SOURCE_DISK=$(lspv | grep -i rootvg | awk '{ print $1 }' | head -n 1)

        # Specifies The Path To The image.data File
        IMAGE_DATA_FILE="/image.data"
        TMP_FILE="/tmp/imagedata.tmp.$$"

        # Creates Custom image.data File To Break Mirror Updating LV_SOURCE_DISK_LIST, COPIES, and PP
        awk -v disk="${SOURCE_DISK}" '
        {
            # Update LV_SOURCE_DISK_LIST (preserve leading whitespace)
            if ($0 ~ /^[[:space:]]*LV_SOURCE_DISK_LIST=/) {
                match($0, /^[[:space:]]*/)
                leading_spaces = substr($0, RSTART, RLENGTH)
                print leading_spaces "LV_SOURCE_DISK_LIST= " disk
            }
            # Modify COPIES and PP (preserve leading whitespace)
            else if ($0 ~ /^[[:space:]]*COPIES= 2$/) {
                match($0, /^[[:space:]]*/)
                leading_spaces = substr($0, RSTART, RLENGTH)
                print leading_spaces "COPIES= 1"
                COPIESFLAG = 1
            }
            else if (COPIESFLAG && $0 ~ /^[[:space:]]*PP= /) {
                match($0, /^[[:space:]]*/)
                leading_spaces = substr($0, RSTART, RLENGTH)
                split($0, parts, "=")                # Split on "=", not "/=/"
                pp_value = parts[2]                  # Extract value after "="
                gsub(/ /, "", pp_value)              # Remove spaces
                print leading_spaces "PP= " int(pp_value / 2)
                COPIESFLAG = 0
            }
            else {
                print $0
            }
        }' "${IMAGE_DATA_FILE}" > "${TMP_FILE}" && mv "${TMP_FILE}" "${IMAGE_DATA_FILE}"

        # Cleans Up Temporary File (If mv Fails)
        if [ -f "${TMP_FILE}" ]; then
            rm -f "${TMP_FILE}"
        fi

        
        echo "The Custom image.data File Breaking The Mirror On The System Backup Was Created"
        echo "Starting System Backup To /dev/${DEVICE}..."
    # Checks To Make Sure Mirrored ROOTVG Backup Was Successful    
        if ! mksysb -eXp /dev/${DEVICE}; then
            echo "Backup Failed"
            echo "Serial:${CURRENT_SERIAL} Exit Code:9 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Mirrored backup Has Failed On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 9
        fi
     fi

    else
        ROOTVG_STATUS="Non-Mirrored ROOTVG"
        echo "Starting System Backup To /dev/${DEVICE}..."
    # Checks To Make Sure Non-Mirrored ROOTVG Backup Was Successful
        if ! mksysb -eXpi /dev/${DEVICE}; then
            echo "Backup Failed."
            echo "Serial:${CURRENT_SERIAL} Exit Code:10 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
            echo "Non-mirrored backup Has Failed On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
            exit 10
        fi
    fi

# Backup Was Successfully Completed
echo "Backup Completed Successfully."
echo "${CURRENT_SERIAL}" > "${SERIAL_FILE}"
echo "Serial:${CURRENT_SERIAL} Exit Code:0 Date:${CURRENT_DATE} Time:${TIME} ROOTVG Status:${ROOTVG_STATUS}" >> "${SYSBAK_LOG}"
echo "Backup Was Successful On ${HOSTNAME}." | mail -s "${HOSTNAME} Backup Report" ${CLIENT_RECIPIENT}
exit 0
