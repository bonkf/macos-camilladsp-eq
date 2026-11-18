#!/usr/bin/env python3
"""Zero-dependency macOS CoreAudio output device helper (stdlib ctypes only)."""

from __future__ import annotations

import ctypes
import sys

COREAUDIO_PATH = "/System/Library/Frameworks/CoreAudio.framework/CoreAudio"
COREFOUNDATION_PATH = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"


def _fourcc(code: str) -> int:
    raw = code.encode("ascii")
    if len(raw) != 4:
        raise ValueError(f"FourCC must be 4 ASCII bytes, got {code!r}")
    return int.from_bytes(raw, "big")


kAudioObjectSystemObject = 1
kAudioObjectUnknown = 0

kAudioObjectPropertyScopeGlobal = _fourcc("glob")
kAudioDevicePropertyScopeOutput = _fourcc("outp")
kAudioObjectPropertyElementMain = 0

kAudioHardwarePropertyDevices = _fourcc("dev#")
kAudioHardwarePropertyDefaultOutputDevice = _fourcc("dOut")
kAudioDevicePropertyStreams = _fourcc("stm#")
kAudioObjectPropertyName = _fourcc("lnam")

kCFStringEncodingUTF8 = 0x08000100


class CoreAudioError(RuntimeError):
    """Raised when a CoreAudio or CoreFoundation call fails."""


class AudioObjectPropertyAddress(ctypes.Structure):
    _fields_ = [
        ("mSelector", ctypes.c_uint32),
        ("mScope", ctypes.c_uint32),
        ("mElement", ctypes.c_uint32),
    ]


_frameworks = None


def _load_frameworks():
    global _frameworks
    if _frameworks is not None:
        return _frameworks

    try:
        ca = ctypes.CDLL(COREAUDIO_PATH)
        cf = ctypes.CDLL(COREFOUNDATION_PATH)
    except OSError as exc:
        raise CoreAudioError(
            f"Failed to load macOS CoreAudio/CoreFoundation frameworks: {exc}"
        ) from exc

    ca.AudioObjectGetPropertyDataSize.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(AudioObjectPropertyAddress),
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint32),
    ]
    ca.AudioObjectGetPropertyDataSize.restype = ctypes.c_int32

    ca.AudioObjectGetPropertyData.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(AudioObjectPropertyAddress),
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.c_void_p,
    ]
    ca.AudioObjectGetPropertyData.restype = ctypes.c_int32

    ca.AudioObjectSetPropertyData.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(AudioObjectPropertyAddress),
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_void_p,
    ]
    ca.AudioObjectSetPropertyData.restype = ctypes.c_int32

    cf.CFStringGetLength.argtypes = [ctypes.c_void_p]
    cf.CFStringGetLength.restype = ctypes.c_long

    cf.CFStringGetMaximumSizeForEncoding.argtypes = [ctypes.c_long, ctypes.c_uint32]
    cf.CFStringGetMaximumSizeForEncoding.restype = ctypes.c_long

    cf.CFStringGetCString.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_long,
        ctypes.c_uint32,
    ]
    cf.CFStringGetCString.restype = ctypes.c_uint8

    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None

    _frameworks = (ca, cf)
    return _frameworks


def _get_device_ids(ca) -> list[int]:
    addr = AudioObjectPropertyAddress(
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    )
    data_size = ctypes.c_uint32(0)
    status = ca.AudioObjectGetPropertyDataSize(
        kAudioObjectSystemObject,
        ctypes.byref(addr),
        0,
        None,
        ctypes.byref(data_size),
    )
    if status != 0:
        raise CoreAudioError(
            f"AudioObjectGetPropertyDataSize('dev#') failed with OSStatus {status}"
        )

    count = data_size.value // ctypes.sizeof(ctypes.c_uint32)
    if count == 0:
        return []

    buf_size = ctypes.c_uint32(count * ctypes.sizeof(ctypes.c_uint32))
    devices = (ctypes.c_uint32 * count)()
    status = ca.AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        ctypes.byref(addr),
        0,
        None,
        ctypes.byref(buf_size),
        ctypes.cast(devices, ctypes.c_void_p),
    )
    if status != 0:
        raise CoreAudioError(
            f"AudioObjectGetPropertyData('dev#') failed with OSStatus {status}"
        )

    actual_count = buf_size.value // ctypes.sizeof(ctypes.c_uint32)
    return [int(devices[i]) for i in range(min(count, actual_count))]


def _has_output_streams(ca, device_id: int) -> bool:
    addr = AudioObjectPropertyAddress(
        kAudioDevicePropertyStreams,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain,
    )
    data_size = ctypes.c_uint32(0)
    status = ca.AudioObjectGetPropertyDataSize(
        device_id,
        ctypes.byref(addr),
        0,
        None,
        ctypes.byref(data_size),
    )
    return status == 0 and data_size.value > 0


def _get_device_name(ca, cf, device_id: int) -> str:
    addr = AudioObjectPropertyAddress(
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    )
    cf_str = ctypes.c_void_p(None)
    data_size = ctypes.c_uint32(ctypes.sizeof(ctypes.c_void_p))
    status = ca.AudioObjectGetPropertyData(
        device_id,
        ctypes.byref(addr),
        0,
        None,
        ctypes.byref(data_size),
        ctypes.byref(cf_str),
    )
    if status != 0:
        raise CoreAudioError(
            f"AudioObjectGetPropertyData('lnam') failed for device {device_id} with OSStatus {status}"
        )
    if not cf_str.value:
        return ""

    try:
        length = cf.CFStringGetLength(cf_str)
        max_size = cf.CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1
        buf = ctypes.create_string_buffer(max_size)
        if not cf.CFStringGetCString(cf_str, buf, max_size, kCFStringEncodingUTF8):
            raise CoreAudioError(f"CFStringGetCString failed for device {device_id}")
        return buf.value.decode("utf-8")
    finally:
        cf.CFRelease(cf_str)


def _iter_output_devices() -> list[tuple[int, str]]:
    ca, cf = _load_frameworks()
    results: list[tuple[int, str]] = []
    for dev_id in _get_device_ids(ca):
        if not _has_output_streams(ca, dev_id):
            continue
        try:
            name = _get_device_name(ca, cf, dev_id)
        except CoreAudioError:
            continue
        results.append((dev_id, name))
    return results


def list_output_devices() -> list[str]:
    """Return localized names of all output-capable CoreAudio devices."""
    return [name for _, name in _iter_output_devices()]


def get_default_output_device() -> str:
    """Return the localized name of the current macOS default output device."""
    ca, cf = _load_frameworks()
    addr = AudioObjectPropertyAddress(
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    )
    dev_id = ctypes.c_uint32(kAudioObjectUnknown)
    data_size = ctypes.c_uint32(ctypes.sizeof(ctypes.c_uint32))
    status = ca.AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        ctypes.byref(addr),
        0,
        None,
        ctypes.byref(data_size),
        ctypes.byref(dev_id),
    )
    if status != 0:
        raise CoreAudioError(
            f"AudioObjectGetPropertyData('dOut') failed with OSStatus {status}"
        )
    if dev_id.value == kAudioObjectUnknown:
        raise CoreAudioError(
            "CoreAudio reported no default output device (kAudioObjectUnknown)"
        )
    return _get_device_name(ca, cf, dev_id.value)


def set_default_output_device(name: str) -> None:
    """Set the macOS default output device by exact localized name."""
    ca, _ = _load_frameworks()
    matched_id = None
    for dev_id, dev_name in _iter_output_devices():
        if dev_name == name:
            matched_id = dev_id
            break

    if matched_id is None:
        raise LookupError(f"Output audio device not found: {name!r}")

    addr = AudioObjectPropertyAddress(
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    )
    target = ctypes.c_uint32(matched_id)
    status = ca.AudioObjectSetPropertyData(
        kAudioObjectSystemObject,
        ctypes.byref(addr),
        0,
        None,
        ctypes.sizeof(target),
        ctypes.byref(target),
    )
    if status != 0:
        raise CoreAudioError(
            f"AudioObjectSetPropertyData('dOut') failed for {name!r} (device {matched_id}) with OSStatus {status}"
        )


def _usage() -> int:
    print(
        f"Usage: {sys.argv[0]} {{list|current|set <exact-name>}}",
        file=sys.stderr,
    )
    return 2


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if not args:
        return _usage()

    cmd = args[0]
    try:
        if cmd == "list" and len(args) == 1:
            for dev in list_output_devices():
                print(dev)
            return 0
        if cmd == "current" and len(args) == 1:
            print(get_default_output_device())
            return 0
        if cmd == "set" and len(args) == 2:
            set_default_output_device(args[1])
            return 0
        return _usage()
    except (CoreAudioError, LookupError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
