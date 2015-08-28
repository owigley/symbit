#!/bin/bash

#
# For MAC OS / XCode crash symbolicate troubleshooting
#
# Displays symbolication information for an Apple .crash file(s). Uses the binary
# uuid to identify matching files. Run symbit from a directory containing the following files:
# You need
#    crash file(s) AND
#    xcarchive bundle(s) AND/OR
#    dsym directory(s) WITH .app bundle(s) AND/OR .ipa bundle(s)
#
# WARN: IPA files are renamed to .zip files, and also expanded in-place
#
# Shows if the crash file can already be symbolicated with the dSYMs
# supplied. Displays the matching dSYM and application binaries. Searches
# recursively in current directory. Unzips any zip files found first. Renames
# ipa files also.
#
# usage:
#   Put .dSYM .app .ipa .xcarchive bundle(s) into a directory with the .crash file(s)
#   Run symbit in same directory
#   Files may be supplied in zip file also - they are unzipped in-place.
#
# (c) 2015 owigley  
#

TMP=/tmp/$$_a.log
TMPR=/tmp/$$_b.log
TMPS=/tmp/$$_c.log
TMPT=/tmp/$$_d.log

echo "============================================"
echo "      symbit symbolicator info              "
echo "============================================"

#
# finds dsym files to match the uuid env variable
#
function syms
{
  found=0

  find .  -name "*.dSYM">${TMPT}

  while read i; do
      #does the dsym dir have a file with same name as binary
      dsfile=`find "${i}"  -name "${1}"`

      if [ "${dsfile}" = "" ] ; then
          #cannot find the binary in the dsym
          continue
      fi

      # dump app architectures to tmp file
      dwarfdump --uuid "${dsfile}">${TMPR}

      while read p; do
        tudid=`echo ${p//[-._]/} | cut -d ' ' -f 2`

        if [ "${tudid}" = "${uuid}" ] ; then
            echo -e '\t' " ... found the corresponding dsym = $i"
            found=1
        fi
      done <${TMPR}

  done <${TMPT}

  if [ ${found} -eq 0 ] ; then
     echo -e '\t' " ... WARN: unable to find dSYM file with name $1 and uuid ${uuid}"
  fi
}


#
# finds app bundles
#
function apps
{
  find .  -name "*.app" >${TMPS}

  while read i; do
      filename=$(basename "$i")
      extension="${filename##*.}"
      filename="${filename%.*}"

      # dump the apps multiple architectures to tmp file
      dwarfdump --uuid "${i}/${filename}">${TMP}

      while read p; do
        #hudid=`echo ${p} | cut -d ' ' -f 2`
        tudid=`echo ${p//[-._]/} | cut -d ' ' -f 2`

        export arch=`echo ${p} | cut -d ')' -f 1 | cut -d '(' -f 2`

        if [ "${tudid}" = "${uuid}" ] ; then
            echo -e '\t' " ... found the matching binary uuid in \"$i/$filename\" for architecture \"${arch}\""

            syms $filename
        fi
      done <${TMP}

    done <${TMPS}
}

#
#  renames ipa files to zip files
#
function findipas
{
  #echo find ipas
  for i in `find .  -type f -name "*.ipa" ` ; do
      basename=$(basename "$i")
      filename="${i%.*}"
      #echo filename is $filename/ipa
      mkdir -p $filename/ipa
      #echo moving "${i}" "$filename/ipa/${basename}.zip" >>/tmp/u.log
      mv "${i}" "$filename/ipa/${basename}.zip"
  done
}

#
#  extracts and deletes any zip
#
function extract
{
  for i in `find . -type f  -name "*.zip" ` ; do
   #   echo unzipping $i
      filename="${i%.*}"
      mkdir -p ${filename}
      unzip  -n -d "${filename}" "${i}" >/dev/null
  done
}

#
# displays total count of relevanmt files
#
function check
{
  echo Total app bundles: `  find .  -name "*.app"  | wc   |  awk ' {print $1} ' `
  echo Total ipa files:   `  find .  -type f -name "*.ipa"  | wc   |  awk ' {print $1} ' `
  echo Total zip files:   `  find .  -type f -name "*.zip"  | wc   |  awk ' {print $1} ' `
  echo Total dSYM dirs:   `  find .  -name "*.dSYM"  | wc   |  awk ' {print $1} ' `
  echo Total crash files: `  find .  -name "*.crash"  | wc   |  awk ' {print $1} ' `
}

###############################################################################
#  main
###############################################################################

#
# crash file(s)
#
crfile=`find .  -name "*.crash"`

findipas
extract

#do again for good measure
findipas
extract

check

for i in $crfile ; do
    echo "Crash file $i ..."

    # Get the binary uuid we are looking for
    uuid=`grep -A 1 Binary ${i} | tail -n 1 | cut -d "<" -f 2 | cut -d ">" -f 1`
    if [ ${#uuid} -ne 32 ] ; then
       echo ERR: Cannot find uuid in crash file in expected format
    fi

    uuid=`echo $uuid | tr '[:lower:]' '[:upper:]'  `
    huuid=`echo ${uuid} | cut -b 1-8`-`echo ${uuid} | cut -b 9-12`-`echo ${uuid} | cut -b 13-16`-`echo ${uuid} | cut -b 17-20`-`echo ${uuid} | cut -b 21-`

    echo -e '\t' " ... the binary uuid in $i is = ${uuid} / ${huuid}"

    if [[ -n $(  mdfind "com_apple_xcode_dsym_uuids == ${huuid}") ]]; then
                echo -e '\t' " ... spotlight already has data for udid ${huuid}. Symbolication should work"
    else
               echo -e '\t' " ... spotlight has no data for udid ${huuid}. Symbolication wont work"
    fi

    # Scan
    apps
done
