#!/usr/bin/env bash
script_version=1.2.2
set -e
echo -e "TrueNAS UPS Workaround v$script_version"
echo -e "Site: https://www.github.com/invario/truenas-ups-workaround"
echo -e "Author: iNVAR\n"

update_check() {
  update_avail() {
    echo -e "Checking for newer version of script"
    latest_script=$(curl -s "https://raw.githubusercontent.com/invario/truenas-ups-workaround/refs/heads/master/truenas_ups_workaround.sh")
    remote_version=$(echo "$latest_script" | sed -n '2p' | cut -f2 -d '=')
    latest_version=$(echo -e "$script_version\n$remote_version" | sort -V | tail -n1)
    echo -e "Remote version: $remote_version"
    if [ "$latest_version" == "$script_version" ]; then
      echo -e "Already running latest version, no need to update"
      return 1
    fi
    return 0
  }
  if update_avail; then
    echo -e "Newer version available"
    read -p 'Download update and restart? (y/N) : ' update_yesno
    if [[ "$update_yesno" == "Y" || "$update_yesno" == "y" ]]; then
      echo -e "Updating..."
      downloadtemp=$(mktemp)
      echo "$latest_script" > "$downloadtemp"
      cat "$downloadtemp" > "$0"
      rm -rf "$downloadtemp"
      echo -e "Restarting..."
      exec "$0" "$@"
    else
      echo -e "Proceeding without updating.\n"
    fi
  fi
}

update_check

if [ -z "$1" ]; then
        echo -e "\nUsage: $0 [target directory]\n"
        exit 1
fi

echo -e "\"$target_dir\" selected for target directory.\n"
continue_yesno=""
if [ -f "$target_dir/usbhid-ups" ]; then
  echo -e "WARNING: \"$target_dir/usbhid-ups\" file already exists. This file will be overwritten during installation.\n"
  read -p 'Continue anyway? (y/N) : ' continue_yesno
  if [[ "$continue_yesno" == "Y" || "$continue_yesno" == "y" ]]; then
    echo -e "Proceeding.\n"
  else
    echo -e "Exiting.\n"
    exit 1
  fi
fi

truenas_deb_version=$(cat /etc/debian_version)
if [ "$truenas_deb_version" == "" ]; then
  echo -e "Error, unable to determine Debian version. \"/etc/debian_version\" is missing/blank. Exiting."
  exit 1
fi
echo -e "Debian $truenas_deb_version indicated.\n"
truenas_deb_version=$(cut -f1 -d '.' /etc/debian_version)
echo -e "Using Docker image \"debian:$truenas_deb_version\"\n"
echo -e "Checking if a POSTINIT entry exists for TrueNAS UPS workaround"
query_initshutdownscript=$(midclt call initshutdownscript.query '[["comment","=","UPS update workaround"]]')
if [ "$query_initshutdownscript" != '[]' ]; then
  echo -e "WARNING: \"UPS update workaround\" POSTINIT entry appears to already exist."
  echo -e "Found the following entries in the system: \n"
  echo "$query_initshutdownscript" | jq
  continue_yesno=""
  echo -e "\n"
  read -p 'If you continue, make sure you remove any duplicate entries after install. Continue anyway? (y/N) : ' continue_yesno
  if [[ "$continue_yesno" == "Y" || "$continue_yesno" == "y" ]]; then
          echo -e "\nProceeding.\n"
  else
          echo -e "\nExiting.\n"
          exit 1
  fi
else
  echo "No entries detected."
fi

set +e
echo -e "What version of NUT should I use?"
echo -e "For a full list of valid tags from the NUT repo, visit https://github.com/networkupstools/nut/tags"
desired_nut_version=""
nut_version_valid=""
while [ "$nut_version_valid" == "" ]
  do
    read -p 'Version must be entered exactly as it appears on the site: [v2.8.5] : ' desired_nut_version
    if [ "$desired_nut_version" == "" ]; then
      echo -e "\nDefault of v2.8.5 selected\n"
      desired_nut_version="v2.8.5"
    fi
    nut_version_valid=$(git ls-remote --tags https://github.com/networkupstools/nut | grep "refs/tags/$desired_nut_version$")
    if [ "$nut_version_valid" != "" ]; then
      break
    fi
    echo -e "$desired_nut_version not found in the https://github.com/networkupstools/nut repo. Please check the tag list and try again.\n"
    desired_nut_version=""
  done
set -e

cleanup() {
  if [ $? -ne 0 ]; then
    echo -e "Error encountered, aborting."
  fi
  trap - EXIT INT TERM
  echo -e "Cleaning up."
  if [ "$temp_container" != "" ]; then
    echo -e "Stopping temp container $temp_container"
    docker container stop $temp_container > /dev/null
  fi
    echo -e "All done."
  exit 1
}

trap cleanup EXIT INT TERM
echo -e "Starting temporary Docker container"
temp_container=$(docker run -d --rm debian:$truenas_deb_version tail -f /dev/null)
echo -e "Container created: $temp_container"
echo -e "Updating and installing packages"
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
  openssl\
  pkg-config \
  python3 \
  time \
  valgrind
echo -e "Beginning build process"
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
echo -e "Copying \"usbhid-ups\" driver from container to \"$target_dir\"\n"
docker cp "$temp_container":/root/nut/drivers/usbhid-ups "$target_dir"
echo -e "Adding POSTINIT startup entry to prepend \"driverpath=$target_dir\" to \"/etc/nut/ups.conf\""
midclt call initshutdownscript.create '{"type": "COMMAND","command": "sed -i.old ''1s;^;driverpath='"$target_dir"'\n;'' /etc/nut/ups.conf && upsdrvctl start","when": "POSTINIT","comment": "UPS update workaround"}' >/dev/null
echo -e "Changes go into effect after every server restart."
echo -e "This script can also restart the UPS driver right now and update the settings WITHOUT restarting the server.\n"
startnew_yesno=""
read -p 'Would you like to do that now? (y/N) : ' startnew_yesno
if [[ "$startnew_yesno" == "Y" || "$startnew_yesno" == "y" ]]; then
  echo -e "Stopping old UPS driver\n"
  upsdrvctl stop
  echo -e "Updating /etc/nut/ups.conf"
  grep "driverpath=" /etc/nut/ups.conf > /dev/null  
  if [ $? -eq 0 ]; then
    echo -e "Existing "driverpath" entry found, updating it"
    sed -i.old 's;^driverpath=.*;driverpath='"$target_dir"';' /etc/nut/ups.conf
  else
    sed -i.old '1s;^;driverpath='"$target_dir"'\n;' /etc/nut/ups.conf
  fi
  echo -e "Starting new UPS driver\n"
  upsdrvctl start
else
  exit 1
fi
echo -e "All done.\n"
