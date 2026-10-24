#!/usr/bin/env python3
"""
iPhone location spoofer over USB.

iOS 16 and older: talks to the `com.apple.dt.simulatelocation` lockdown service
directly. The simulated location sticks until it is cleared or the phone reboots.

iOS 17 and newer: Apple removed that lockdown service, so this uses the
instruments LocationSimulation channel (what Xcode uses) over an RSD tunnel.
Needs `sudo pymobiledevice3 remote tunneld` running in another terminal, and
the location only holds while this process stays connected.

Usage:
    spoof.py                 # map UI at http://127.0.0.1:8765
    spoof.py set LAT LON     # set once (iOS 17+: holds until Ctrl-C)
    spoof.py clear           # back to real GPS
    spoof.py status          # show the connected phone
"""

import argparse
import asyncio
import json
import logging
import struct
import sys
from contextlib import AsyncExitStack, suppress
from pathlib import Path
from typing import Optional

from packaging.version import Version
from pymobiledevice3 import usbmux
from pymobiledevice3.exceptions import (
    AlreadyMountedError,
    DeveloperModeIsNotEnabledError,
    NoDeviceConnectedError,
    PasswordRequiredError,
    PyMobileDevice3Exception,
    TunneldConnectionError,
)
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation
from pymobiledevice3.services.mobile_image_mounter import auto_mount
from pymobiledevice3.tunneld.api import get_tunneld_device_by_udid

SIMULATE_LOCATION_SERVICE = "com.apple.dt.simulatelocation"
SIMULATE_START = 0
SIMULATE_STOP = 1
UI_FILE = Path(__file__).with_name("ui.html")

log = logging.getLogger("spoof")


class SpoofError(Exception):
    """An error with a message meant for the person running the tool."""


class Spoofer:
    def __init__(self) -> None:
        self.lockdown = None
        self.udid: Optional[str] = None
        self.name: Optional[str] = None
        self.ios: Optional[str] = None
        self.devid: Optional[int] = None  # usbmux gives a new id on every re-attach
        self.location: Optional[tuple[float, float]] = None  # where the phone should be
        self.active = False  # whether the phone is there right now
        self._dvt_stack: Optional[AsyncExitStack] = None
        self._dvt_sim: Optional[LocationSimulation] = None
        self._lock = asyncio.Lock()

    @property
    def modern(self) -> bool:
        return self.ios is not None and Version(self.ios) >= Version("17.0")

    def status(self) -> dict:
        return {
            "connected": self.lockdown is not None,
            "name": self.name,
            "udid": self.udid,
            "ios": self.ios,
            "mode": None if self.ios is None else ("dvt" if self.modern else SIMULATE_LOCATION_SERVICE),
            "location": self.location,
            "active": self.active,
        }

    async def connect(self) -> None:
        if self.lockdown is not None:
            return
        # usbmuxd can miss a device that just attached, so give it a few tries.
        for _ in range(5):
            device = await usbmux.select_device(connection_type="USB")
            if device is not None:
                break
            await asyncio.sleep(0.5)
        if device is None:
            raise SpoofError("No iPhone found over USB. Plug it in with a cable, unlock it, and tap Trust.")
        try:
            lockdown = await create_using_usbmux(serial=device.serial, connection_type="USB")
        except PasswordRequiredError:
            raise SpoofError("The iPhone is locked. Unlock it and tap Trust on the prompt, then retry.")
        self.ios = lockdown.product_version
        if Version(self.ios) >= Version("16.0"):
            with suppress(PyMobileDevice3Exception):
                if not await lockdown.get_developer_mode_status():
                    await lockdown.close()
                    raise SpoofError(
                        "Developer Mode is off. On the iPhone: Settings > Privacy & Security > "
                        "Developer Mode, turn it on, and restart."
                    )
        self.lockdown = lockdown
        self.udid = device.serial
        self.devid = device.devid
        self.name = lockdown.short_info.get("DeviceName") or lockdown.display_name
        log.info("connected to %s (iOS %s)", self.name, self.ios)

    async def _mount(self, provider) -> None:
        try:
            await auto_mount(provider)
            log.info("mounted developer disk image")
        except AlreadyMountedError:
            pass
        except DeveloperModeIsNotEnabledError:
            raise SpoofError("Developer Mode is off. Turn it on in Settings > Privacy & Security.")

    # iOS <= 16: raw com.apple.dt.simulatelocation protocol.
    # Each command is a big-endian uint32 opcode; START is followed by the
    # latitude and longitude as length-prefixed decimal strings.

    async def _legacy_send(self, payload: bytes) -> None:
        await self._mount(self.lockdown)
        service = await self.lockdown.start_lockdown_developer_service(SIMULATE_LOCATION_SERVICE)
        try:
            await service.sendall(payload)
        finally:
            await service.aclose()

    @staticmethod
    def _legacy_start_payload(lat: float, lon: float) -> bytes:
        payload = struct.pack(">I", SIMULATE_START)
        for value in (lat, lon):
            encoded = repr(value).encode()
            payload += struct.pack(">I", len(encoded)) + encoded
        return payload

    # iOS >= 17: DVT LocationSimulation, kept open for as long as we run.

    async def _dvt(self) -> LocationSimulation:
        if self._dvt_sim is not None:
            return self._dvt_sim
        try:
            rsd = await get_tunneld_device_by_udid(self.udid)
        except TunneldConnectionError:
            rsd = None
        if rsd is None:
            raise SpoofError(
                f"iOS {self.ios} needs a tunnel. In another terminal run:  "
                "sudo pymobiledevice3 remote tunneld   (leave it running), then retry."
            )
        stack = AsyncExitStack()
        try:
            stack.push_async_callback(rsd.close)
            await self._mount(rsd)
            dvt = await stack.enter_async_context(DvtProvider(rsd))
            self._dvt_sim = await stack.enter_async_context(LocationSimulation(dvt))
        except BaseException:
            await stack.aclose()
            raise
        self._dvt_stack = stack
        return self._dvt_sim

    async def _drop(self) -> None:
        """Forget the connection so the next command reconnects (e.g. after unplugging)."""
        if self._dvt_stack is not None:
            with suppress(Exception):
                await self._dvt_stack.aclose()
        if self.lockdown is not None:
            with suppress(Exception):
                await self.lockdown.close()
        self._dvt_stack = self._dvt_sim = self.lockdown = self.devid = None
        self.active = False

    async def _apply(self) -> None:
        """Push self.location to the phone. Caller holds self._lock."""
        await self.connect()
        lat, lon = self.location
        if self.modern:
            await (await self._dvt()).set(lat, lon)
        else:
            await self._legacy_send(self._legacy_start_payload(lat, lon))
        self.active = True

    async def watch(self, interval: float = 2.0) -> None:
        """
        Keep the phone at self.location across cable drops.

        On iOS 17+ the simulated location dies with the DVT connection, so every tick
        re-sends it (which doubles as a liveness check) and, once the phone is back on
        USB with a fresh tunnel, reconnects and reapplies it.
        """
        last_error = None
        while True:
            await asyncio.sleep(interval)
            if self.location is None:
                continue
            async with self._lock:
                if self.location is None:
                    continue
                try:
                    device = await usbmux.select_device(udid=self.udid, connection_type="USB")
                except Exception:
                    device = None
                if device is None or (self.devid is not None and device.devid != self.devid):
                    if self.lockdown is not None:
                        log.info("iPhone disconnected; will put it back at %.6f, %.6f when it returns", *self.location)
                        await self._drop()
                    continue
                if self.active and not self.modern:
                    continue  # the legacy service keeps the location by itself
                was_active = self.active
                try:
                    # The first apply after a reconnect may mount the disk image, so allow longer.
                    await asyncio.wait_for(self._apply(), timeout=5 if was_active else 120)
                except Exception as e:
                    await self._drop()
                    message = str(e) or repr(e)
                    if message != last_error:
                        log.info("waiting for iPhone: %s", message)
                        last_error = message
                    continue
                last_error = None
                if not was_active:
                    log.info("reconnected; location restored to %.6f, %.6f", *self.location)

    async def _run(self, action) -> None:
        async with self._lock:
            for attempt in (1, 2):
                try:
                    await self.connect()
                    await action()
                    return
                except SpoofError:
                    raise
                except (NoDeviceConnectedError, ConnectionError, OSError, PyMobileDevice3Exception) as e:
                    await self._drop()
                    if attempt == 2:
                        raise SpoofError(f"Lost the iPhone connection: {e!r}") from e

    async def set(self, lat: float, lon: float) -> None:
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise SpoofError("Latitude must be -90..90 and longitude -180..180.")
        # Remember it even if the phone is unplugged right now; watch() applies it later.
        self.location = (lat, lon)
        await self._run(self._apply)
        log.info("location set to %.6f, %.6f", lat, lon)

    async def clear(self) -> None:
        self.location = None

        async def action():
            if self.modern:
                await (await self._dvt()).clear()
            else:
                await self._legacy_send(struct.pack(">I", SIMULATE_STOP))

        await self._run(action)
        self.active = False
        log.info("location cleared, phone is back on real GPS")

    async def close(self) -> None:
        await self._drop()


# Minimal local HTTP server for the map UI. Binds to 127.0.0.1 only.

async def _respond(writer, status: int, body: bytes, ctype: str = "application/json") -> None:
    reason = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 409: "Conflict"}[status]
    writer.write(
        f"HTTP/1.1 {status} {reason}\r\nContent-Type: {ctype}\r\nContent-Length: {len(body)}\r\n"
        "Cache-Control: no-store\r\nConnection: close\r\n\r\n".encode() + body
    )
    await writer.drain()


def make_handler(spoofer: Spoofer, port: int):
    allowed_origins = {f"http://127.0.0.1:{port}", f"http://localhost:{port}"}

    async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            head = await reader.readuntil(b"\r\n\r\n")
            lines = head.decode("latin-1").split("\r\n")
            method, path, _ = lines[0].split(" ", 2)
            headers = {k.strip().lower(): v.strip() for k, v in (l.split(":", 1) for l in lines[1:] if ":" in l)}
            body = await reader.readexactly(int(headers.get("content-length", 0) or 0))

            if method == "GET" and path == "/":
                return await _respond(writer, 200, UI_FILE.read_bytes(), "text/html; charset=utf-8")
            if method == "GET" and path == "/api/status":
                return await _respond(writer, 200, json.dumps(spoofer.status()).encode())
            if method == "POST" and path in ("/api/set", "/api/clear", "/api/connect"):
                # Only our own page may drive the phone; other sites can't send JSON here.
                if headers.get("origin") not in allowed_origins or "application/json" not in headers.get("content-type", ""):
                    return await _respond(writer, 403, b'{"error":"forbidden"}')
                try:
                    if path == "/api/set":
                        data = json.loads(body or b"{}")
                        await spoofer.set(float(data["lat"]), float(data["lon"]))
                    elif path == "/api/clear":
                        await spoofer.clear()
                    else:
                        await spoofer._run(lambda: asyncio.sleep(0))
                except SpoofError as e:
                    return await _respond(writer, 409, json.dumps({"error": str(e), **spoofer.status()}).encode())
                except (KeyError, ValueError):
                    return await _respond(writer, 400, b'{"error":"send {\\"lat\\": number, \\"lon\\": number}"}')
                return await _respond(writer, 200, json.dumps(spoofer.status()).encode())
            await _respond(writer, 404, b'{"error":"not found"}')
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ConnectionError, ValueError):
            pass
        except Exception as e:
            log.exception("request failed")
            with suppress(Exception):
                await _respond(writer, 409, json.dumps({"error": repr(e)}).encode())
        finally:
            with suppress(Exception):
                writer.close()
                await writer.wait_closed()

    return handle


async def serve(spoofer: Spoofer, port: int) -> None:
    with suppress(SpoofError):
        await spoofer._run(lambda: asyncio.sleep(0))
    server = await asyncio.start_server(make_handler(spoofer, port), "127.0.0.1", port)
    watcher = asyncio.create_task(spoofer.watch())  # noqa: F841 (kept alive for the server's lifetime)
    print(f"Map UI: http://127.0.0.1:{port}   (Ctrl-C to quit)")
    async with server:
        await server.serve_forever()


async def main() -> int:
    parser = argparse.ArgumentParser(description="Spoof an iPhone's GPS location over USB.")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="cmd")
    p_set = sub.add_parser("set", help="set a location")
    p_set.add_argument("lat", type=float)
    p_set.add_argument("lon", type=float)
    sub.add_parser("clear", help="restore real GPS")
    sub.add_parser("status", help="show the connected iPhone")
    sub.add_parser("serve", help="run the map UI (default)")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(message)s")
    if not args.verbose:
        logging.getLogger("pymobiledevice3").setLevel(logging.WARNING)

    spoofer = Spoofer()
    try:
        if args.cmd == "set":
            await spoofer.set(args.lat, args.lon)
            if spoofer.modern:
                print("Holding the location (reapplied after cable drops). Ctrl-C to stop and restore real GPS.")
                try:
                    await spoofer.watch()
                finally:
                    with suppress(Exception):
                        await spoofer.clear()
        elif args.cmd == "clear":
            await spoofer.clear()
        elif args.cmd == "status":
            await spoofer._run(lambda: asyncio.sleep(0))
            print(json.dumps(spoofer.status(), indent=2))
        else:
            await serve(spoofer, args.port)
    except SpoofError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    finally:
        await spoofer.close()
    return 0


if __name__ == "__main__":
    with suppress(KeyboardInterrupt):
        sys.exit(asyncio.run(main()))
