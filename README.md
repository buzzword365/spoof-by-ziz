# iPhone location spoofer

Sets your iPhone's GPS location over a USB cable, using Apple's own developer services.
Click a spot on the map to teleport, or walk there at a set speed.

> **⚠️ Disclaimer:** This tool is for app testing, development and personal use on a device you own.
> Many apps forbid location spoofing in their terms of service (for example location-based games,
> dating, delivery and rideshare apps), and using it there can get your account banned. Using it to
> fake attendance or check-ins, commit fraud, or get around region or betting restrictions may be
> illegal where you live. You are responsible for how you use it. It is provided as is, with no
> warranty; use it at your own risk. Not affiliated with or endorsed by Apple.

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

## Notes
- **Privacy & security:** the map server listens on `127.0.0.1` only, so nothing else on your
  network can control your phone, and it only accepts commands from its own page. The only
  outside requests are map tiles and place searches from OpenStreetMap.
- **Map data:** map tiles and search come from OpenStreetMap's free servers, which are meant for
  light use. Please follow their [tile](https://operations.osmfoundation.org/policies/tiles/) and
  [search](https://operations.osmfoundation.org/policies/nominatim/) usage policies.
- **The Mac app isn't notarized.** Build it yourself with `./app/build.sh`. A prebuilt `.app`
  downloaded from the internet will be blocked by macOS Gatekeeper.

## Credits
Built on [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) (GPL-3.0),
[Leaflet](https://leafletjs.com) and [OpenStreetMap](https://www.openstreetmap.org/copyright) data.

## License
Copyright (C) 2026 buzzword365

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY. See
[LICENSE](LICENSE) for the full text.
