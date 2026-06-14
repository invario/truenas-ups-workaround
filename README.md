Bash script builds NUT `usbhid-ups` and sets TrueNAS Scale/CE to use that instead for users experiencing false "replace battery" UPS alerts stemming from an outdated version of NUT. I am currently running this on TrueNAS CE v25.10.3 with my APC BVK750M2 connected via USB. If you're using a UPS that is not connected via USB, or you're not getting these false alerts, **this is not for you.**

## What's The Problem?

[TrueNAS Scale/Community Edition (CE)](https://www.truenas.com/truenas-community-edition/) has a service to connect to and monitor a UPS. This service runs [Network UPS Tools (NUT)](https://github.com/networkupstools/nut/). TrueNAS Scale/CE currently runs on [NUT v2.8.0](https://github.com/networkupstools/nut/releases/tag/v2.8.0-signed) which was released in 2022.

[This post](https://forums.truenas.com/t/closed-update-nut-to-the-latest-version/50033/13) on the TrueNAS forums describes the issue as well as https://github.com/networkupstools/nut/issues/2347. Namely, for some UPS connected to NUT, the software keeps throwing false "replace battery" alerts. Fixes for some models were implemented in [NUT v2.8.4](https://networkupstools.org/docs/release-notes.chunked/NUT_Release_Notes.html#2-3-release-notes-for-nut-2-8-4-what%E2%80%99s-new-since-2-8-3) with additional models being added in later updates.

TrueNAS has closed the discussion on the topic and simply stated that they follow the version of NUT that is in the Debian package repo (which isn't an unreasonable position to have.) Since TrueNAS is on Debian 12 (Bookworm), this is NUT v2.8.0.  Once TrueNAS updates to Debian 13 (Trixie), NUT will follow but the version of NUT that would be included with Trixie is still very outdated (v2.8.1-5)

## My Solution

The part of NUT that causes the false alarms is the `usbhid-ups` driver which is simply one executable file. I wrote a Bash script that only needs to be run once and it does the following:
 
 1. Checks to see if this script is the latest version. If not, offers an option to update itself.
 2. Downloads a new version of NUT and builds the `usbhid-ups` driver, all inside a matching version Debian Docker container (TrueNAS Scale/CE v25.10.3 is currently on Debian 12), then copies the `usbhid-ups` driver into the directory specified on the command line. 
 3. Adds a POSTINIT entry to TrueNAS that prepends `driverpath` to `/etc/nut/ups.conf` on every server restart (since changes auto-revert.) Note: if you restart your UPS service via TrueNAS, the `driverpath` entry to `/etc/nut/ups.conf` will be lost and you must either reboot, or run the script again with `--skip-build`. `driverpath` forces NUT to look elsewhere for the driver. In this case, the new one we just compiled. Also, beginning with v1.6.0, the following lines will also be appended to `ups.conf`:
```
lbrb_log_delay_without_calibrating=1
lbrb_log_delay_sec=3
onlinedischarge_calibration=1
```
See https://networkupstools.org/docs/man/usbhid-ups.html for more information about these options and why they are necessary.

 4. Optionally, immediately modify `/etc/nut/ups.conf` and reload the UPS driver for changes to be made effective immediately without a server restart.

## How Do I Install This?

 1. Ensure the TrueNAS UPS service is already enabled and running.
 2. SSH/Open a console to your TrueNAS server.
 3. Select a directory you want to store the single `usbhid-ups` executable. I have a dataset on my own pool called `custom` to store custom stuff, so I made a `nut` subdirectory there. 
 4. Download the script somewhere (`/root` is fine), make it executable, then run it. Specifying `--skipbuild` on the command line skips the build process and assumes the `usbhid-ups` is already present in the selected directory.
 ```
 curl -o truenas_ups_workaround.sh https://raw.githubusercontent.com/invario/truenas-ups-workaround/refs/heads/master/truenas_ups_workaround.sh
 chmod 700 truenas_ups_workaround.sh
 ./truenas_ups_workaround.sh [--skipbuild] <FULL_PATH_TO_YOUR_DIRECTORY>
 ```
 5. Follow the various prompts. That's it!
