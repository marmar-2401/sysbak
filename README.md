Documentation On Sysbak
-------------------------

Use Case:
----------
- To replace IBM's system tape backups with a cheaper alternative of USB devices.

Files Associated with sysbak Before the Script is Run for the First Time:
----------------------------------------------------------------------
- sysbakrotate.sh: The script that creates a log rotation for sysbak.sh. It is intended to be run as a cron job on the same interval as sysbak.sh.
- rotatetest.sh: A script to test sysbakrotate.sh by making the /var/log/sysbak_log exceed its size limit. This triggers a log rotation to archive the old logs to /var/log/sysbak_log.archive.
- sysbak.sh: The mksysb script with error handling to automate system backups to USBs on a regular basis via a cron job.

Files Associated with sysbak After the Script is Run:
------------------------------------------------------
- /var/log/sysbak_log: The sysbak.sh log file, which includes the date, time, exit code, and rootvg type of the system during the backup. Exit codes can be found using 'ksh sysbak.sh --help' or by concatenating the sysbak.sh file.
- backup_details: This file captures STDIN and STDERR output from sysbak.sh. You can use 'tail -f backup_details' to watch the script run in real-time or 'cat' to view the details of the last backup. This file is overwritten every time the script is re-run.
- usb_details: A file created only if multiple USBs are detected during the system backup. It records the server serial number and the location codes of both USBs on the server and emails them to the recipient specified in the script. This file is removed after the email is sent, resetting it for the next run.
- usb_serial: A file that stores the serial number of the USB used during a system backup. It is used to cross-reference the USB serial number in subsequent backups, ensuring the USB has been changed.
- /var/log/sysbak_log.archive: The archive location for rotated logs.
- /image.data: The file where custom configurations for the backup are stored.

File Locations:
----------------
- /var/log/sysbak_log & /var/log/sysbak_log.archive: Located in the /var/log/ directory.
- sysbakrotate.sh, rotatetest.sh, sysbak.sh, backup_details, usb_details, and usb_serial: These files will be located in the sysbak directory, wherever it is decided to place it.
- /image.data: Created in the root directory.

Client Requirements to Use This Script:
---------------------------------------
1) Three Supported USBs (Preferably SanDisk):
   - One for the initial backup that will be stored away.
   - The other two should be cycled monthly or on the desired backup interval.
   - Typically, these should be larger than 10 GB.
   - If all mksysb backups are stored on the MAINAPP server, ensure the USB sizes account for the number of LPARs multiplied by 10 GB.
   
2) Sendmail Must Be Installed:
   - This is required to send email alerts to the SPN dashboard if an error occurs.

Configuration of sysbakrotate.sh:
-----------------------------------
- Should be located in the sysbak directory.
- MAX_LOG_SIZE: This variable must be adjusted to set the size limit (in bytes) for sysbak_log before it is rotated to archive.
- Cron job: Set to run on the same interval as sysbak.sh, preferably a minute or two before. This checks the log size and rotates it to archive if it exceeds the MAX_LOG_SIZE.

* * * * * ksh /path/to/sysbakrotate.sh &

Configuration of sysbak.sh:
---------------------------
- Should be located in the sysbak directory.
- Client_RECIPIENT: This variable needs to be configured to specify where email alerts are sent if errors occur during automated updates.
- Line 147 in sysbak.sh needs to be adjusted to account for the size change of the USB in the -lt (Less Than) test in MBs (Only adjust if all LPAR backups are stored on the MAINAPP server).

* * * * * ksh /path/to/sysbak.sh &

Using rotatetest.sh:
---------------------
NOTE: Do not run this until sysbak.sh has run at least once to populate the sysbak_log file.

- Should be located in the sysbak directory.
- This script ensures that sysbakrotate.sh works as intended.
- To test, run 'ksh rotatetest.sh &' and then check /var/log/sysbak_log.archive. The current log should have rotated.

How to Override the Same USB Being Used for a Backup:
-----------------------------------------------------
- usb_serial: This clears the stored USB serial number.

Run the following command:
ksh sysbak.sh &

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


Commands To Check If A /image.data Mirror Is Broken (Important For Backing Up A Mirrored System)
---------------------------------------------------------------------------------------------------
- cat /image.data | grep 'COPIES='
- cat /image.data | grep 'LV_SOURCE_DISK_LIST='
- cat /image.data | grep 'PP='

===========================================
          Restoring from MKSYSB  
===========================================

--- 1. Access the HMC ---
- Log in to the **HMC**.
- Locate the **server frame** by **serial number** and **LPAR name**.

--- 2. Power Down the LPAR ---
- Select the LPAR that needs to be restored.
- Go to **Actions → Shutdown** and choose the appropriate shutdown method.
  - Use **Immediate** if recovering a system.

--- 3. Activate the LPAR in SMS Mode ---
- Select the **same LPAR**, go to **Actions → Activate**.
- Select **Change Partition Configuration** (pick any option that allows advanced settings).
- Change **Boot Mode** to **System Management Services (SMS)**.
- Click **Finish**.

--- 4. Access the Console via SSH ---
- SSH into the **HMC**.
- Run:
    vtmenu
- Select the **server frame** you are working on.
- Select the **partition** you just activated.

--- 5. Boot from the USB (via SMS Menu) ---
- In the SMS menu:
  - Select **5** → **Select Boot Options**.
  - Select **Install/Boot Device**.
  - Select **7** → **List All Devices**.
  - Press **N** for the next list if needed.
  - Locate the **USB device**, select its number, and press **Enter**.
  - Select **2** → **Normal Mode Boot**, then press **Enter**.
  - Select **1** → **Yes** (This will boot from the USB).

--- 6. Start the Installation Process ---
- Select **2** → **Change/Show Installation Settings and Install**.
- Select **1** → **Disks for Installation**.
  - Ensure only **one good operational disk** is selected.
- Select **0** → **Continue with Choices Indicated Above**.
- Installation starts and will drop to a shell when completed.

Note:
------
Only difference in **mirrored** setups is the need to remirror the disk once restoration is complete.

>>> Steps to Remirror rootvg <<<
1. Ensure the **rootvg** disks are healthy.
2. Add the second disk to **rootvg**:
      extendvg -f rootvg <disk>
3. Mirror the volume group:
      mirrorvg -S rootvg <disk>
4. Update bootable information:
      bosboot -ad /dev/<rootvg disk>
      bosboot -ad /dev/ipldevice
5. Set the bootlist:
      bootlist -m normal hdisk0 hdisk1
      bootlist -m service cd0 rmt0 hdisk0 hdisk1
6. Save the configuration:
      savebase -v


