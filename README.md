Docker Compose YAML intended to be used with TrueNAS Scale/CE as a workaround for users experiencing false "replace battery" UPS alerts stemming from an outdated version of NUT. I am currently running this on TrueNAS CE v25.10.3 with my APC BVK750M2 connected via USB.

## What's The Problem?

[TrueNAS Scale/Community Edition (CE)](https://www.truenas.com/truenas-community-edition/) has a service to connect to and monitor a UPS. This service runs [Network UPS Tools (NUT)](https://github.com/networkupstools/nut/). The latest version of TrueNAS Scale/CE as of this writing runs on [NUT v2.8.0](https://github.com/networkupstools/nut/releases/tag/v2.8.0-signed) which was released in 2022.

[This post](https://forums.truenas.com/t/closed-update-nut-to-the-latest-version/50033/13) on the TrueNAS forums describes the issue. Namely, for some UPS connected to NUT, the software keeps throwing false "replace battery" alerts. Fixes for some models were implemented in [NUT v2.8.4](https://networkupstools.org/docs/release-notes.chunked/NUT_Release_Notes.html#2-3-release-notes-for-nut-2-8-4-what%E2%80%99s-new-since-2-8-3) with additional models being added in later updates.

TrueNAS has closed the discussion on the topic and simply stated that they follow the version of NUT that is in the Debian package repo (which isn't an unreasonable position to have.) Since TrueNAS is on Debian 12 (Bookworm), this is NUT v2.8.0.  Once TrueNAS updates to Debian 13 (Trixie), NUT will follow but the version of NUT that would be included is still very outdated (v2.8.1-5)

## The Old Workaround
I won't get into the details, but the old workaround involved compiling a newer version of NUT, disabling rootfs protection on TrueNAS and clobbering the outdated NUT files with the new ones. This is bad for a couple of reasons, but mostly because:

 1. You're disabling safety checks. 🚨
 2. You're messing with parts of TrueNAS that other parts may rely on and may have unintended effects (reporting /notification services, etc.) 😬
 3. Every time you update TrueNAS, your changes are undone. 😖 

## The Better Solution

 TrueNAS Scale/CE's UPS service allows you to switch it to "slave" mode, which makes it connect to a "master" instance of NUT. The workaround is to run the latest version of NUT in "master" mode within a Docker container, then let TrueNAS connect as a slave to the container. This is significantly better because:
 
 1. No safety checks disabled. 😌
 2. No unforeseen consequences with TrueNAS's functionality. 🙊
 3. Changes are retained across updates since it is Dockerized. 🎉

## How Do I Use This?
Installation is simple and completely reversible.

 1. Go to Services on your TrueNAS GUI and stop the TrueNAS UPS service: <img width="245" height="48" alt="image" src="https://github.com/user-attachments/assets/ad08604a-5587-46cd-b180-7edc240a6c7d" />
 2. Go to Apps on your TrueNAS GUI, and click Discover Apps, and then press the 3 dots for more options to Install via YAML: <img width="193" height="119" alt="image" src="https://github.com/user-attachments/assets/49ff37a2-84c2-4150-8820-59751371d460" />
 3. Name your app ('nut' is fine), and paste the contents of the YAML file in the space.
 4. Tweak the YAML if necessary and if you know what you're doing, but it should run fine as it is.
 5. Press the "Save" button and wait. This will take a while since it is downloading and building NUT from scratch.
 6. Once it is complete, go back to the TrueNAS UPS service and edit the settings as such: <img width="375" height="241" alt="image" src="https://github.com/user-attachments/assets/abc7ed0b-d3af-4cae-93c6-44594c6823df" />
 7. Start the UPS service.
 8. That's it. Everything should work at this point!

## Additional Info:
Some of this information is included as comments in the YAML already
- TrueNAS follows the Debian package repo for good reasons. Software in the repo is tested and vetted and is "stable". Getting the latest version from the GIT NUT repo can introduce bugs or other issues. **In other words, USE AT YOUR OWN RISK.**
- My UPS is connected via USB and uses NUT's `usbups-hid` driver. I have only tested it using this. If your UPS is connected via some other way, this is not the workaround for you to use. Of course, you can still try it and undo your changes if you find issues.
- On server restarts, you will receive a UPS communications lost error because the Docker container hasn't started yet. Once it starts up, the error will be cleared.
- The Docker container publishes the NUT service on port 3493. TrueNAS's UPS service will connect to that. Do not change this.
- The Docker container automatically creates a `upsmon` user for TrueNAS to use to connect. Do not change this.
- Some UPS devices (like my APC) randomly disconnect/reconnect resulting in the USB Device ID changing. This option allows the container to dynamically update the USB device list (aka hotplug). If you don't experience this problem, you can safely comment it out.
  ```
  device_cgroup_rules:
  - 'c 189:* rmw'
  ```
- For TrueNAS GID 126 is the `nut` group and UID 125 is the `nut` user.  This container runs as root but changes to UID 568, which is the TrueNAS `apps` user, but uses GID 126 to ensure it can access the USB device.
