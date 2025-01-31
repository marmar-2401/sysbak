#!/bin/ksh

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
TMP_FILE="/tmp/imagedata.tmp.$$"  # Use /tmp to avoid permission issues

# Use awk to preserve indentation while updating LV_SOURCE_DISK_LIST, COPIES, and PP
awk -v disk="$SOURCE_DISK" '
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
}' "$IMAGE_DATA_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$IMAGE_DATA_FILE"

# Cleanup temporary file (if mv fails)
if [ -f "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
fi
