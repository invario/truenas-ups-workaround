Bash script builds NUT `usbhid-ups` and sets TrueNAS Scale/CE to use that instead for users experiencing false "replace battery" UPS alerts stemming from an outdated version of NUT. I am currently running this on TrueNAS CE v25.10.3 with my APC BVK750M2 connected via USB. If you're using a UPS that is not connected via USB, or you're not getting these false alerts, **this is not for you.**

## What's The Problem?

[TrueNAS Scale/Community Edition (CE)](https://www.truenas.com/truenas-community-edition/) has a service to connect to and monitor a UPS. This service runs [Network UPS Tools (NUT)](https://github.com/networkupstools/nut/). TrueNAS Scale/CE currently runs on [NUT v2.8.0](https://github.com/networkupstools/nut/releases/tag/v2.8.0-signed) which was released in 2022.

[This post](https://forums.truenas.com/t/closed-update-nut-to-the-latest-version/50033/13) on the TrueNAS forums describes the issue. Namely, for some UPS connected to NUT, the software keeps throwing false "replace battery" alerts. Fixes for some models were implemented in [NUT v2.8.4](https://networkupstools.org/docs/release-notes.chunked/NUT_Release_Notes.html#2-3-release-notes-for-nut-2-8-4-what%E2%80%99s-new-since-2-8-3) with additional models being added in later updates.

TrueNAS has closed the discussion on the topic and simply stated that they follow the version of NUT that is in the Debian package repo (which isn't an unreasonable position to have.) Since TrueNAS is on Debian 12 (Bookworm), this is NUT v2.8.0.  Once TrueNAS updates to Debian 13 (Trixie), NUT will follow but the version of NUT that would be included is still very outdated (v2.8.1-5)

## My Solution

 Originally, my solution ran the new NUT version in a Docker container as a "master" and the TrueNAS UPS service connected to it as a "slave". This worked decently, but it still felt a bit clunky. Also, the workaround broke the ability to power off the UPS on a shutdown.
 
 The current solution is much better. The part of NUT that causes the false alarms is the `usbhid-ups` driver which is simply one executable file. I wrote a Bash script that only needs to be run once and it does the following:
 
 1. Downloads a new version of NUT and builds the `usbhid-ups` driver, all inside a matching Debian Docker container (TrueNAS Scale/CE v25.10.3 is currently on Debian 12.11)
 2. Copy the `usbhid-ups` driver into the directory specified on the command line
 3. Modifies the `/etc/nut/ups.conf` to include a line at the beginning for `driverpath=/YOUR_DIRECTORY_CHOICE` which allows NUT to load the new driver instead.
 4. Calls the TrueNAS API to add a POSTINIT entry that performs step #3 on every server restart since it will auto-revert. Note: if you make changes to your UPS settings and then save the settings, the `driverpath` modification to `/etc/nut/ups.conf` will also be lost.
 5. Reloads the UPS driver for you so you don't need to restart the server.

## How Do I Install This?

 1. SSH/Open a console to your TrueNAS server.
 2. Download the script somewhere and make it executable. `/root` is fine.
 ```
 curl -o truenas_ups_workaround.sh https://raw.githubusercontent.com/invario/truenas-ups-workaround/refs/heads/master/truenas_ups_workaround.sh
 chmod 700 truenas_ups_workaround.sh
 ```
 3. Select a directory you want to store the single `usbhid-ups` executable. I have a dataset on my own pool called `custom` to store custom stuff, so I made a `nut` subdirectory there.
 4. Run the script and specify the directory you picked in #3 above as the first and only command line parameter.
 ```
 ./truenas_ups_workaround.sh /mnt/MYPOOL/custom/nut
 ```
 5. Follow the prompts. The script will check automatically for an update to itself. 
 
 6. If the script detects a POSTINIT entry exists that matches the one it will generate, it will warn you, but still allow you to proceed. Make sure you remove any duplicate entries in your `TrueNAS->System->Advanced Settings->Init/Shutdown Scripts` section.
 
 ## TODO
 
 Adding more safety checks, prompts, etc. Maybe the ability to automatically delete POSTINIT entries that it finds
