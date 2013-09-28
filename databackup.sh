#!/bin/sh
#
# Script: databackup.sh
# Version: 1.2
#
# Purpose:
# Perform an Automatic Backup based on inputs provided in a Config file.
#
# License: LGPLv2
# Author: Kiran J. Holla
#         http://www.kiranjholla.com/
#
# Description:
#    This script provides a utility that can be used to automatically backup various
#    elements of a website. Individual TAR files are created as per configuration and
#    then optionally uploaded to Dropbox.
#
#    The upload to Dropbox functionality makes use of the script provided by Andrea Fabrizi
#    at http://www.andreafabrizi.it/?dropbox_uploader
#
#
# Modification Log:
#    v1.0      Nov 25, 2012    Initial version
#
#    v1.1      Jan 14, 2013    Fixed some bugs where the usage was getting printed multiple
#                              times and the number of days for the directory backup was
#                              yielding negative numbers when the year changes.
#
#    v1.2      Mar 16, 2013    Included the --create-options option in the mysqldump command
#                              to ensure that the auto increment parameter is not skipped in
#                              dump file.
#

print_usage()
{
   # Function to print the Usage instructions for this script.
   #
   echo "Usage:"
   echo "   databackup.sh <Backup Name> <Param 1> [<Param 2> [<Param 3> [. . .]]]"
   echo " "
   echo "   Backup Name: The name by which the consolidated backup should be named. A file by name"
   echo "                BACKUP_<Backup Name>_<Date & Time>.tar is created."
   echo " "
   echo "    Parameters: Each parameter marks a set of Backup instructions that need to be documented"
   echo "                in the .databackup_config file that should exist in the same directory as this"
   echo "                script."
   echo " "
   echo "Sample Configuration File Contents:"
   echo "   PARAM1:BKPTYPE:DIR"
   echo "   PARAM1:BKPFORI:FULL"
   echo "   PARAM1:BKPATTR1:WebFiles"
   echo "   PARAM1:BKPATTR2:/home/user/httpd/www"
   echo "   PARAM1:BKPATTR3:/home/user/backups"
   echo " "
   echo "   PARAM2:BKPTYPE:DB"
   echo "   PARAM2:BKPFORI:FULL"
   echo "   PARAM2:BKPATTR1:WebDatabase"
   echo "   PARAM2:BKPATTR2:my_database"
   echo "   PARAM2:BKPATTR3:/home/user/backups"
   echo " "
   echo "Then, run the script as below:"
   echo "   databackup.sh WebBackup PARAM1 PARAM2"
   echo " "

}

backup_db()
{
   # Function to dump a MYSQL database and then package the resulting
   # SQL file in a tar.
   #
   # This function assumes that the configuration parameter ${DB_BACKUP_USER}
   # is set to any user name that possesses sufficient privileges on the DB
   # being backed up using mysqldump.
   #
   # This function further assumes that a .my.cnf file has been created and
   # placed in the home directory of the user running this script and that
   # file contains the correct password for the user name being used.
   #


   DB_BACKUP_USER=`grep 'DB_BACKUP_USER' ${CNFGFILE} | cut -d":" -f2`
   DB_HOST=`grep 'DB_HOST' ${CNFGFILE} | cut -d":" -f2`

   echo "Dumping Database " >> ${MAILFILE}
   echo " " >> ${MAILFILE}

   mysqldump -u ${DB_BACKUP_USER} -h ${DB_HOST} --skip-opt --add-drop-table --create-options --complete-insert --extended-insert --single-transaction --result-file="${BKPATTR3}/BKPFULL_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.sql" ${BKPATTR2}

   cd ${BKPATTR3}
   tar --create --verbose --file "BKPFULL_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.tar" "BKPFULL_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.sql"

   echo " " >> ${MAILFILE}

   if [ -f "${BKPATTR3}/BKPFULL_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.tar" ]
   then
      echo "Database backed up to ${BKPATTR3}/BKP${BKPTYPE}_${BKPATTR1}_${TMTODAY}.tar" >> ${MAILFILE}

      rm "${BKPATTR3}/BKPFULL_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.sql"
      return 0
   else
      echo "Error in Database backup." >> ${MAILFILE}
      return 1
   fi

}

backup_dir()
{
   # Function to backup a physical directory. There are two options;
   #
   #    1: Full Backup - this option creates a full backup for the
   #       entire directory including any subdirectories within it.
   #
   #    2: Incremental Backup - this option takes a backup of only
   #       those files that were modified after the LASTRUN date
   #

   echo "Backing up directory ${BKPATTR2}" >> ${MAILFILE}
   BKPOK=1

   LASTRUN=`grep ${BKPMODE} ${CNFGFILE} | grep 'LASTRUN' | cut -d":" -f3`           #Last Run Date in YYYYMMDD

   if [ "${BKPFORI}" = "FULL" ] || [ -z ${LASTRUN} ]
   then
      # Perform Full Backup

      tar --create --verbose --recursion --file ${BKPATTR3}/BKP${BKPFORI}_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.tar ${BKPATTR2}

      BKPOK=$?
      echo "Tar Return Status ${BKPOK}" >> ${MAILFILE}

   else
      # Perform Incremental Backup

      echo "Backup was last run on ${LASTRUN}" >> ${MAILFILE}
      DAYSLAST=$((($(date -u -d "${DTTODAY}" +%s) - $(date -u -d "${LASTRUN}" +%s)) / 86400))

      echo "Days since last run ${DAYSLAST}" >> ${MAILFILE}


      #Create an empty TAR file, which can then be used to add the modified files
      tar --create --verbose --file ${BKPATTR3}/BKP${BKPFORI}_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.tar
      find ${BKPATTR2} -type f -mtime -${DAYSLAST} -exec tar --append --verbose --dereference --file ${BKPATTR3}/BKP${BKPFORI}_${BKPTYPE}_${BKPATTR1}_${TMTODAY}.tar "{}" \;

      BKPOK=$?
      echo "Tar Return Status ${BKPOK}" >> ${MAILFILE}

   fi

   if [ ${BKPOK} -eq 0 ]
   then

      echo " " >> ${MAILFILE}
      echo "TAR created." >> ${MAILFILE}

      #Backup has been successful
      #Replace the LASTRUN date in Config file with today's date
      cat ${CNFGFILE} | grep -v "${BKPMODE}:LASTRUN" > ${CNFGTEMP}
      echo "${BKPMODE}:LASTRUN:${DTTODAY}" >> ${CNFGTEMP}
      cat ${CNFGTEMP} > ${CNFGFILE}

      rm -f ${CNFGTEMP}

      echo "Backed up the directory." >> ${MAILFILE}
      return 0
   else
      echo "Error while backing up directory!" >> ${MAILFILE}
      return 1
   fi
}

export CNFGFILE
export CNFGTEMP
export MAILFILE
export TMTODAY
export DTTODAY
export BKPFORI
export BKPATTR1
export BKPATTR2
export BKPATTR3
export BKPMODE

SCRPTDIR=`dirname $0`
CNFGFILE=${SCRPTDIR}/.databackup_config
CNFGTEMP=${SCRPTDIR}/.databackup_conftemp
MAILFILE=${SCRPTDIR}/mailfile_temp.txt
MAILADDR=`grep 'BKP_MAIL_RECIPIENT' ${CNFGFILE} | cut -d":" -f2`


trap 'cat ${MAILFILE} | mail -s "Backup Error!" ${MAILADDR}; rm -f ${MAILFILE}; rm -f ${CNFGTEMP}; exit' 1 2 3 15

TMTODAY=`date +%Y%m%d%H%M%S`
DTTODAY=`date +%Y%m%d`



# The name that is to be used to create the consolidated backup file
if [ "$1" ]
then
   BKPNAME=${1}
   shift
else
   print_usage >> ${MAILFILE}
   exit 1
fi

if [ "$1" ]
then
   echo "Running Backup at ${TMTODAY} for ${BKPNAME}" > ${MAILFILE}
   echo " " >> ${MAILFILE}

   while [ "$1" ]
   do

      echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> ${MAILFILE}
      echo "Running for $1 . . ." >> ${MAILFILE}

      BKPMODE=${1}
      BKPTYPE=`grep ${BKPMODE} ${CNFGFILE} | grep 'BKPTYPE' | cut -d":" -f3`           #DB or DIR
      BKPFORI=`grep ${BKPMODE} ${CNFGFILE} | grep 'BKPFORI' | cut -d":" -f3`           #Full or Incremental
      BKPATTR1=`grep ${BKPMODE} ${CNFGFILE} | grep 'BKPATTR1' | cut -d":" -f3`         #Site Name
      BKPATTR2=`grep ${BKPMODE} ${CNFGFILE} | grep 'BKPATTR2' | cut -d":" -f3`         #DB or DIR
      BKPATTR3=`grep ${BKPMODE} ${CNFGFILE} | grep 'BKPATTR3' | cut -d":" -f3`         #Backup Directory

      echo "BKPTYPE = ${BKPTYPE}" >> ${MAILFILE}
      echo "BKPFORI = ${BKPFORI}" >> ${MAILFILE}
      echo "BKPATTR1 = ${BKPATTR1}" >> ${MAILFILE}
      echo "BKPATTR2 = ${BKPATTR2}" >> ${MAILFILE}
      echo "BKPATTR3 = ${BKPATTR3}" >> ${MAILFILE}

      echo " " >> ${MAILFILE}

      if [ "$BKPTYPE" ]
      then
         case $BKPTYPE
         in
            "DB") backup_db ;;
            "DIR") backup_dir ;;
         esac
      fi

      shift
   done

   echo "Creating Consolidated Backup TAR . . ." >> ${MAILFILE}

   cd ${BKPATTR3}
   tar --create --verbose --file BACKUP_${BKPNAME}_${TMTODAY}.tar BKP*${TMTODAY}.tar

   if [ -f ${BKPATTR3}/BACKUP_${BKPNAME}_${TMTODAY}.tar ]
   then
      echo "Consolidated Backup TAR created successfully!" >> ${MAILFILE}
      echo " " >> ${MAILFILE}
      echo "Removing intermediate backups . . ." >> ${MAILFILE}

      rm ${BKPATTR3}/BKP*${TMTODAY}.tar >> ${MAILFILE}

      cd ${SCRPTDIR}

      if [ -x ./dropbox_uploader/dropbox_uploader.sh ]
      then
         echo "Backing up ${BKPATTR3}/BACKUP_${BKPNAME}_${TMTODAY}.tar to Dropbox. . ." >> ${MAILFILE}
         ./dropbox_uploader/dropbox_uploader.sh upload ${BKPATTR3}/BACKUP_${BKPNAME}_${TMTODAY}.tar BACKUP_${BKPNAME}_${TMTODAY}.tar >> ${MAILFILE}
         if [ $(grep -c 'DONE' ${MAILFILE}) -ne 0 ]
         then
            rm ${BKPATTR3}/BACKUP_${BKPNAME}_${TMTODAY}.tar
            echo "Removed Consolidated TAR after upload to Dropbox" >> ${MAILFILE}
         fi
      else
         echo "Dropbox uploader not found. Skipping Dropbox backup!" >> ${MAILFILE}
      fi
   fi
else
   print_usage >> ${MAILFILE}
   exit 1
fi

cat ${MAILFILE} | mail -s "Backup Completed!" ${MAILADDR}

rm -f ${MAILFILE}
rm -f ${CNFGTEMP}
