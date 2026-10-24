# iPhone location spoofer

Sets your iPhone's GPS location over a USB cable, using Apple's own developer services.
Click a spot on the map to teleport, or walk there at a set speed.

## Setup (once)
1. `pipx install pymobiledevice3`
2. iPhone: plug in by cable, unlock, tap **Trust**.
3. iPhone: Settings → Privacy & Security → **Developer Mode** → on (it restarts).

## iOS 17 or newer: start the tunnel
Apple removed `com.apple.dt.simulatelocation` from lockdown in iOS 17, so newer phones go through
an encrypted tunnel. Leave this running in its own terminal:

    sudo pymobiledevice3 remote tunneld

## Run
    ./run.sh                    # map UI at http://127.0.0.1:8765
    ./run.sh set 48.8584 2.2945 # one-shot (iOS 17+: holds until Ctrl-C)
    ./run.sh clear              # back to real GPS
    ./run.sh status

The first run downloads and mounts the Developer Disk Image automatically.

## Mac app
    ./app/build.sh

Builds **Spoof by Ziz.app** into /Applications. Opening it starts the tunnel (asks for your
password once) and the spoofer, and shows the map in its own window. Quitting it stops
everything, and the phone goes back to real GPS.

## How long it lasts
- iOS 16 and older: stays until you `clear` or reboot the phone.
- iOS 17 and newer: lasts only while `run.sh` is running. Quit it and the phone goes back to real GPS.
  If the cable drops, the spoofer puts your location back automatically a few seconds after it reconnects.
