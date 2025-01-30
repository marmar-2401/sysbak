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

TMP_FILE="/imagedata.tmp"

echo "Updating LV_SOURCE_DISK_LIST To ${SOURCE_DISK}..."
sed "s/LV_SOURCE_DISK_LIST=.*/LV_SOURCE_DISK_LIST= ${SOURCE_DISK}/" "${IMAGE_DATA_FILE}" > "${TMP_FILE}" && mv "${TMP_FILE}" "${IMAGE_DATA_FILE}"


COPIESFLAG=0  # Initialize flag

# Read file line by line
while read LINE; do
  if [ "$LINE" = "COPIES= 2" ]; then
    COPIESFLAG=1
    echo "COPIES= 1" >> "$TMP_FILE"
  else
    if [ $COPIESFLAG -eq 1 ]; then
      PP=$(echo "$LINE" | awk '{print $1}')
      if [ "$PP" = "PP=" ]; then
        PPNUM=$(echo "$LINE" | awk '{print $2}')
        PPNUMNEW=$((PPNUM / 2))
        echo "PP= $PPNUMNEW" >> "$TMP_FILE"
        COPIESFLAG=0
      else
        echo "$LINE" >> "$TMP_FILE"
      fi
    else
      echo "$LINE" >> "$TMP_FILE"
    fi
  fi
done < /image.data

# Replace the original file after processing
mv "$TMP_FILE" /image.data
