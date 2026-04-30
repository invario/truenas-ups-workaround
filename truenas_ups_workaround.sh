#!/usr/bin/bash
if [ -z "$1" ]; then
        echo -e "\nUsage: $0 [target directory]\n"
        exit 1
fi
target_dir=$1
if [ ! -d "$target_dir" ]; then
  echo -e "Target directory does not exist. Please create it first.\n"
  exit 1
fi

echo -e """$target_dir"" selected for target directory.\n"
continue_yesno=""
if [ -f "$target_dir/usbhid-ups" ]; then
  echo -e "WARNING: ""$target_dir/usbhid-ups"" file already exists. This file will be overwritten during installation.\n"
  read -p 'Continue anyway? (y/N) : ' continue_yesno
  if [ "$continue_yesno" == "Y" ] || [ "$continue_yesno" == "y" ]; then
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
echo -e "Debian $truenas_deb_version detected\n"

echo -e "Checking if a POSTINIT entry exists for TrueNAS UPS workaround"
query_initshutdownscript=$(midclt call initshutdownscript.query '[["comment","=","UPS update workaround"]]')
if [ "$query_initshutdownscript" != '[]' ]; then
  echo -e "WARNING: \"UPS update workaround\" POSTINIT entry appears to already exist."
  echo -e "Found the following entries in the system: \n"
  echo "$query_initshutdownscript" | jq
  continue_yesno=""
  read -p 'If you continue, make sure you remove any duplicate entries after install. Continue anyway? (y/N) : ' continue_yesno
  if [ "$continue_yesno" == "Y" ] || [ "$continue_yesno" == "y" ]; then
          echo -e "Proceeding.\n"
  else
          echo -e "Exiting.\n"
          exit 1
  fi
else
  echo "No entries detected."
fi

desired_nut_version=""
echo -e "\nWhat version of NUT should I use?"
echo -e "For a full list of valid tags from the NUT repo, visit https://github.com/networkupstools/nut/tags"
read -p 'Version must be entered exactly as it appears on the site: [v2.8.5] : ' desired_nut_version
if [ "$desired_nut_version" == "" ] || [ "$desired_nut_version" == "" ]; then
  echo -e "\nDefault of v2.8.5 selected\n"
  desired_nut_version="v2.8.5"
fi

cleanup() {
  trap - EXIT INT TERM
  echo -e "Cleaning up."
  if [ "$temp_container" != "" ]; then
    echo -e "Stopping temp container $temp_container"
    docker container stop $temp_container > /dev/null
  fi
  exit 1
}

trap cleanup EXIT INT TERM
temp_container=$(docker run -d --rm debian:$truenas_deb_version tail -f /dev/null)
docker exec "$temp_container" apt-get update
docker exec "$temp_container" apt-get -y install \
  autoconf \
  automake \
  python3 \
  git \
  libtool \
  g++ \
  pkg-config \
  libnss3-dev \
  libnss3-tools \
  openssl\
  libssl-dev \
  libgd-dev \
  clang \
  gcc \
  cppcheck \
  ccache \
  time \
  perl \
  curl \
  make \
  libltdl-dev \
  binutils \
  valgrind \
  libcppunit-dev \
  augeas-tools \
  libaugeas-dev \
  augeas-lenses \
  libusb-dev \
  libusb-1.0-0-dev \
  libglib2.0-dev \
  libi2c-dev \
  libmodbus-dev \
  libsnmp-dev \
  libpowerman0-dev \
  libfreeipmi-dev \
  libipmimonitoring-dev \
  libavahi-common-dev \
  libavahi-core-dev \
  libavahi-client-dev \
  dpkg-dev
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
echo -e "Copying \"usbhid-ups\" driver to \"$target_dir\"\n"
docker cp "$temp_container":/root/nut/drivers/usbhid-ups "$target_dir"
echo -e "Adding POSTINIT startup entry to prepend \"driverpath=$target_dir\" to \"/etc/nut/ups.conf\""
midclt call initshutdownscript.create '{"type": "COMMAND","command": "sed -i.old ''1s;^;driverpath='"$target_dir"'\n;'' /etc/nut/ups.conf && upsdrvctl start","when": "POSTINIT","comment": "UPS update workaround"}' >/dev/null
echo -e "Build and copy completed and startup POSTINIT entry added."
echo -e "Changes go into effect after every server restart."
echo -e "This script can also restart the UPS driver right now and update the settings WITHOUT restarting the server.\n"
startnew_yesno=""
read -p 'Would you like to do that now? (y/N) : ' startnew_yesno
if [ "$startnew_yesno" == "Y" ] || [ "$startnew_yesno" == "y" ]; then
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
