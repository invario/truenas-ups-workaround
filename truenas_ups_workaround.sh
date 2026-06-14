#!/usr/bin/env bash
script_version=1.6.0
#
# Copyright (C) 2026 iNVAR
# TrueNAS UPS Workaround - A Bash script workaround for TrueNAS Scale/CE that
# lets you update the UPS service NUT usbhid-ups driver, for users
# experiencing false "replace battery" alarms.
#
# This program is free software: you can redistribute it and/or modify
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY. See the GNU General Public License for
# more details. <http://www.gnu.org/licenses/>.
#

# shellcheck disable=SC2120
update_check() {
  update_avail() {
    echo -e "\e[33mChecking for newer version of script\e[0m"
    local latest_script remote_version latest_version downloadtemp
    if ! latest_script=$(curl -s --fail-with-body "https://raw.githubusercontent.com/invario/truenas-ups-workaround/refs/heads/master/truenas_ups_workaround.sh"); then
      echo "$latest_script"
      echo -e "\e[31mUnable to check for latest version. Skipping...\e[0m"
      return 1
    fi
    remote_version=$(echo "$latest_script" | sed -n '2p' | cut -f2 -d '=')
    latest_version=$(echo -e "$script_version\n$remote_version" | sort -V | tail -n1)
    echo "Remote version: $remote_version"
    if [[ "$latest_version" == "$script_version" ]]; then
      echo -e "\e[32m✓ Running latest version.\e[0m\n"
      return 1
    fi
    return 0
  }
  if update_avail; then
    echo -e "\e[33mNewer version available.\e[0m"
    read -r -p 'Download update and restart? (y/N) : ' update_yesno
    if [[ "$update_yesno" == "Y" || "$update_yesno" == "y" ]]; then
      echo "Updating..."
      local downloadtemp
      downloadtemp=$(mktemp)
      echo "$latest_script" >"$downloadtemp"
      cat "$downloadtemp" >"$0"
      rm -rf "$downloadtemp"
      echo "Restarting..."
      exec "$0" "$@"
    else
      echo -e "\e[33mProceeding without update.\e[0m\n"
    fi
  fi
}

cleanup_and_exit() {
  if [[ $? -ne 0 ]]; then
    errors="true"
    echo -e "\n\e[31mAborting due to error.\e[0m"
  fi
  trap - EXIT INT TERM
  echo -e "\e[33mCleaning up.\e[0m"
  if [[ "$temp_container" != "" ]]; then
    echo "Stopping temp container: $temp_container"
    set +e
    if ! docker container stop "$temp_container" >/dev/null; then
      echo -e "\e[31mUnable to stop temp container\e[0m"
    fi
    set -e
  fi
  if [[ "$errors" == "true" ]]; then
    echo -e "\e[31mDone and exiting, with errors encountered.\e[0m"
  else
    echo -e "\e[32m✓ Done and exiting, successfully completed.\e[0m"
  fi
  exit 1
}

build_nut() {
  local truenas_deb_version
  truenas_deb_version=$(cat /etc/debian_version)
  echo -e "Detected TrueNAS host running Debian $truenas_deb_version\n"
  truenas_deb_version=$(cut -f1 -d '.' /etc/debian_version)
  echo -e "Using Docker image \"debian:$truenas_deb_version\"\n"
  set +e
  echo "What version of NUT should I use?"
  echo "Visit <https://github.com/networkupstools/nut/tags> for a list of tags"
  local desired_nut_version=""
  local nut_version_valid=""
  while [ "$nut_version_valid" == "" ]; do
    read -r -p 'Version must be entered exactly as it appears on the site [v2.8.5] : ' desired_nut_version
    if [[ "$desired_nut_version" == "" ]]; then
      echo -e "\nDefault of v2.8.5 selected\n"
      desired_nut_version="v2.8.5"
    fi
    nut_version_valid=$(git ls-remote --tags https://github.com/networkupstools/nut "refs/tags/$desired_nut_version")
    if [[ "$nut_version_valid" != "" ]]; then
      break
    fi
    echo -e "\e[31m$desired_nut_version not found\e[0m in the https://github.com/networkupstools/nut repo. Please check the tag list and try again.\n"
    desired_nut_version=""
  done
  set -e

  echo "Starting temporary Docker container"
  temp_container=$(docker run -d --rm debian:"$truenas_deb_version" tail -f /dev/null)
  echo "Container created: $temp_container"
  echo "Updating and installing packages"
  docker exec "$temp_container" apt-get update
  docker exec "$temp_container" apt-get -y install \
    augeas-lenses \
    augeas-tools \
    autoconf \
    automake \
    binutils \
    ccache \
    clang \
    cppcheck \
    curl \
    dpkg-dev \
    g++ \
    gcc \
    git \
    libaugeas-dev \
    libavahi-client-dev \
    libavahi-common-dev \
    libavahi-core-dev \
    libcppunit-dev \
    libfreeipmi-dev \
    libgd-dev \
    libglib2.0-dev \
    libi2c-dev \
    libipmimonitoring-dev \
    libltdl-dev \
    libmodbus-dev \
    libnss3-dev \
    libnss3-tools \
    libpowerman0-dev \
    libsnmp-dev \
    libssl-dev \
    libtool \
    libusb-1.0-0-dev \
    libusb-dev \
    make \
    openssl \
    pkg-config \
    python3 \
    time \
    valgrind
  echo "Beginning build process"
  docker exec "$temp_container" git clone --branch "$desired_nut_version" https://github.com/networkupstools/nut /root/nut
  docker exec "$temp_container" /bin/sh -c "cd /root/nut; /root/nut/autogen.sh"
  docker exec "$temp_container" /bin/sh -c "cd /root/nut; \
    deb_host_multiarch=\$(/usr/bin/dpkg-architecture -qdeb_host_multiarch); \
    /root/nut/configure \
    --prefix= \
    --sysconfdir=/etc/nut \
    --includedir=/usr/include \
    --mandir=/usr/share/man \
    --libdir=/lib/\$deb_host_multiarch \
    --libexecdir=/usr/libexec \
    --with-ssl \
    --with-nss \
    --with-cgi \
    --with-dev \
    --enable-static \
    --with-statepath=/run/nut \
    --with-altpidpath=/run/nut \
    --with-drvpath=/lib/nut \
    --with-cgipath=/usr/lib/cgi-bin/nut \
    --with-htmlpath=/usr/share/nut/www \
    --with-pidpath=/run/nut \
    --datadir=/usr/share/nut \
    --with-pkgconfig-dir=/usr/lib/\$deb_host_multiarch/pkgconfig \
    --with-user=nut \
    --with-group=nut \
    --with-udev-dir=/lib/udev \
    --with-systemdsystemunitdir=/lib/systemd/system \
    --with-systemdshutdowndir=/lib/systemd/system-shutdown \
    --with-systemdtmpfilesdir=/usr/lib/tmpfiles.d"
  docker exec "$temp_container" /bin/sh -c "cd /root/nut; make -j $(nproc) all-drivers"
  echo -e "\e[32mBuild completed\e[32m.\nCopying \"usbhid-ups\" driver from container to \"$dest_dir\"\n"
  docker cp "$temp_container":/root/nut/drivers/usbhid-ups "$dest_dir"
}

check_postinit() {
  echo -e "\e[33mChecking if a POSTINIT entry exists already\e[0m"
  query_initshutdownscript=$(midclt call initshutdownscript.query '[["comment","=","UPS update workaround"],["enabled","=",true]]' '{"select": ["id","comment","command"]}')
  if [[ "$query_initshutdownscript" != '[]' ]]; then
    echo -e "\e[31mWARNING\e[0m: \"UPS update workaround\" POSTINIT entries exist.\n"
    echo -e "The following ($(jq 'length' <<<"$query_initshutdownscript")) were found:\n"
    jq -c '.[] | {id, comment, command}' <<<"$query_initshutdownscript"
    continue_yesno=""
    echo -e "\nWhat would you like to do with them?
  - (R)emove (permanent)
  - (D)isable (you can undo this manually if needed)
  - (I)gnore (remove the duplicates yourself manually)
  - (A)bort and exit"
    read -r -p '(R)emove, (D)isable, (I)gnore, or (A)bort: ' continue_yesno
    echo ""
    case "$continue_yesno" in
    [rR])
      readarray -t all_entry_ids < <(jq -c '.[].id' <<<"$query_initshutdownscript")
      set +e
      for entry_id in "${all_entry_ids[@]}"; do
        # initshutdownscript.delete ALWAYS returns TRUE even if the "$entry_id" doesn't exist.
        # The only failure we can evaluate for is if the midclt command fails to execute.
        if midclt call initshutdownscript.delete "$entry_id" >/dev/null; then
          echo -e "\e[33mDeleted POSTINIT entry $entry_id.\e[0m"
        else
          echo -e "\e[31mUnable to delete entry $entry_id\e[0m"
          exit 1
        fi
      done
      set -e
      ;;

    [dD])
      set +e
      readarray -t all_entry_ids < <(jq -c '.[].id' <<<"$query_initshutdownscript")
      for entry_id in "${all_entry_ids[@]}"; do
        if midclt call initshutdownscript.update "$entry_id" '{"enabled":false}' >/dev/null; then
          echo "Disabled POSTINIT entry $entry_id."
        else
          echo "Unable to disable entry $entry_id"
          break
        fi
      done
      set -e
      ;;
    [iI])
      echo -e "\e[33mIgnoring existing entry and proceeding.\e[0m"
      ;;
    [aA] | *)
      echo "Aborting."
      exit 0
      ;;
    esac
  else
    echo -e "\e[32mNo entries detected.\e[0m"
  fi
}

set -e
script_header="TrueNAS UPS Workaround v$script_version
Site: https://www.github.com/invario/truenas-ups-workaround
Author: iNVAR
"

help="
Usage: $0 [OPTION]... [FULL PATH TO DESTINATION]
  Valid switches:

  -s, --skip-build      skip building ""usbhid-ups"" driver, only install config
  -h, --help            show this screen
"

echo "$script_header"

trap cleanup_and_exit EXIT INT TERM

update_check

if [[ -z "$1" ]]; then
  echo "$help"
  trap - EXIT
  exit 0
fi

dest_dir=${!#}

while [[ $# -gt 0 ]]; do
  case $1 in
  -s | --skip-build)
    skipbuild=true
    shift # Shift past the flag
    ;;
  -h | --help)
    echo "$help"
    trap - EXIT
    exit 0
    ;;
  --) # Manual end of options
    shift
    break
    ;;
  *) # Handle unknown options or positional arguments
    if [[ "${1:0:1}" == "-" ]]; then
      echo -e "Error, invalid switch: \"$1\""
      echo "$help"
      exit 1
    fi
    POSITIONAL_ARGS+=("$1")
    shift
    ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -eq 0 ]]; then
  echo "Error, no destination directory provided"
  echo "$help"
  exit 1
fi

if [[ ${#POSITIONAL_ARGS[@]} -gt 1 ]]; then
  echo "Error, too many arguments provided"
  echo "$help"
  exit 1
fi

if [[ ! -f "/etc/debian_version" ]]; then
  echo -e "Error, unable to determine Debian version. \"/etc/debian_version\" is missing/blank. Exiting."
  exit 1
fi

continue_yesno=""
if [[ "$skipbuild" ]]; then
  if [[ ! -f "$dest_dir/usbhid-ups" ]]; then
    echo -e "\e[31mWARNING\e[0m: \"$dest_dir/usbhid-ups\" file doesn't exist and ""--skipbuild"" was specified.\n"
    read -r -p 'Continue anyway? (y/N) : ' continue_yesno
    if [[ "$continue_yesno" == "Y" || "$continue_yesno" == "y" ]]; then
      echo -e "Proceeding.\n"
    else
      echo -e "Exiting.\n"
      exit 1
    fi
  fi
else
  if [[ -f "$dest_dir/usbhid-ups" ]]; then
    echo -e "\e[31mWARNING\e[0m: \"$dest_dir/usbhid-ups\" file already exists. This file will be overwritten during installation.\n"
    read -r -p 'Continue anyway? (y/N) : ' continue_yesno
    if [[ "$continue_yesno" == "Y" || "$continue_yesno" == "y" ]]; then
      echo -e "Proceeding.\n"
    else
      echo -e "Exiting.\n"
      exit 1
    fi
  fi
  build_nut
fi

modify_upsconf() {
  set +e
  if grep "driverpath=" /etc/nut/ups.conf >/dev/null; then
    set -e
    sed -i.old 's;^driverpath=.*;driverpath='"$dest_dir"';' /etc/nut/ups.conf
    echo -e "\e[32m✓ Existing \"driverpath\" line found and updated.\e[0m"
  else
    set -e
    sed -i.old '1s;^;driverpath='"$dest_dir"'\n;' /etc/nut/ups.conf
    echo -e "\e[32m✓ Prepended new \"driverpath\" line \e[0m"
  fi
  if grep "lbrb_log_delay_without_calibrating" /etc/nut/ups.conf >/dev/null; then
    set -e
    sed -i.old 's;lbrb_log_delay_without_calibrating.*;lbrb_log_delay_without_calibrating=1;' /etc/nut/ups.conf
    echo -e "\e[32m✓ Existing \"lbrb_log_delay_without_calibrating\" line found and updated.\e[0m"
  else
    set -e
    echo "lbrb_log_delay_without_calibrating=1" >>/etc/nut/ups.conf
    echo -e "\e[32m✓ Appended new \"lbrb_log_delay_without_calibrating\" line \e[0m"
  fi
  if grep "lbrb_log_delay_sec" /etc/nut/ups.conf >/dev/null; then
    set -e
    sed -i.old 's;lbrb_log_delay_sec.*;lbrb_log_delay_sec=3;' /etc/nut/ups.conf
    echo -e "\e[32m✓ Existing \"lbrb_log_delay_sec\" line found and updated.\e[0m"
  else
    set -e
    echo "lbrb_log_delay_sec=3" >>/etc/nut/ups.conf
    echo -e "\e[32m✓ Appended new \"lbrb_log_delay_sec\" line \e[0m"
  fi
  if grep "onlinedischarge_calibration" /etc/nut/ups.conf >/dev/null; then
    set -e
    sed -i.old 's;onlinedischarge_calibration.*;onlinedischarge_calibration=1;' /etc/nut/ups.conf
    echo -e "\e[32m✓ Existing \"onlinedischarge_calibration\" line found and updated.\e[0m"
  else
    set -e
    echo "onlinedischarge_calibration=1" >>/etc/nut/ups.conf
    echo -e "\e[32m✓ Appended new \"onlinedischarge_calibration\" line \e[0m"
  fi
}

check_postinit
echo -e "\e[33mAdding new POSTINIT startup entry\e[0m"
if ! new_postinit_id=$(midclt call initshutdownscript.create '{"type": "COMMAND", "command": "sed -i.old '"'"'1s;^;driverpath='"$dest_dir"'\\n;'"'"' /etc/nut/ups.conf && echo \"lbrb_log_delay_without_calibrating=1\\nlbrb_log_delay_sec=3\\nonlinedischarge_calibration=1\">>/etc/nut/ups.conf && upsdrvctl start","when": "POSTINIT","comment": "UPS update workaround"}' | jq '.id'); then
  echo -e "\e[31mUnable to add new POSTINIT startup entry\e[0m"
  exit 1
fi
echo -e "\e[32m✓ New POSTINIT startup entry ID $new_postinit_id added.\e[0m\n"
echo -e "Changes are effective after every server restart.
I can also reload the driver immediately WITHOUT restarting the server.\n"
startnew_yesno=""
read -r -p 'Would you like to do that? (y/N) : ' startnew_yesno
if [[ "$startnew_yesno" == "Y" || "$startnew_yesno" == "y" ]]; then
  modify_upsconf
  set -e
  echo -e "\e[33mStopping existing UPS driver\e[0m\n"
  if ! upsdrvctl -D stop; then
    echo -e "\e[31mFailed to stop existing UPS driver\e[0m"
    exit 1
  fi
  for i in {30..1}; do
    echo -en "\r\e[33mWaiting 30 seconds for driver to auto reload: $i "
    sleep 1
  done
  echo -e "\r\e[33mWaiting 30 seconds for driver to auto reload: done\e[0m"
  if ! pgrep "usbhid-ups" >/dev/null; then
    echo -e "\e[33mERROR\e\[0m: \"usbhid-ups\" UPS driver did not auto reload properly, exiting.\e[0m"
    exit 1
  fi
  echo -e "\e[32m✓ UPS driver started.\e[0m"
fi
cleanup_and_exit
