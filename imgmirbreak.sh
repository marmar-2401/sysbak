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
