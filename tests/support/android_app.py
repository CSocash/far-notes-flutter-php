"""Builds the Flutter Android app for device tests and starts an emulator to run it on.

The emulator reaches this Mac as 10.0.2.2, not 127.0.0.1, so the test server's address is rewritten before
it is compiled in with --dart-define=FAR_NOTES_API_URL. The APK is copied to .test-data/android-build, so a
later build in app/ can't swap it out mid-run.
"""

import os
import shutil
import subprocess
import time
from pathlib import Path
from urllib.parse import urlparse

from tests.support.server import ROOT, TEST_DATA

APP_DIR = ROOT / "app"
APK_OUTPUT = APP_DIR / "build/app/outputs/flutter-apk/app-debug.apk"
APK_PATH = TEST_DATA / "android-build/app-debug.apk"
APP_PACKAGE = "com.farnotes.studylog"
SDK = Path(os.environ.get("ANDROID_HOME") or Path.home() / "Library/Android/sdk")
ADB = str(SDK / "platform-tools/adb")
EMULATOR = str(SDK / "emulator/emulator")
FLUTTER = shutil.which("flutter") or os.path.expanduser("~/development/flutter/bin/flutter")
EMULATOR_HOST = "10.0.2.2"   # the Mac, as seen from inside the Android emulator


def emulator_url(api_url):
    """http://127.0.0.1:3100 -> http://10.0.2.2:3100. Other hosts are left alone."""
    url = urlparse(api_url)
    if url.hostname in ("127.0.0.1", "localhost"):
        return url._replace(netloc=f"{EMULATOR_HOST}:{url.port}").geturl()
    return api_url


def build_android_app(api_url):
    """Builds app-debug.apk with the emulator's address for api_url compiled in, and returns its path."""
    result = subprocess.run(
        [FLUTTER, "build", "apk", "--debug", f"--dart-define=FAR_NOTES_API_URL={emulator_url(api_url)}"],
        cwd=APP_DIR, capture_output=True, text=True, env={**os.environ, "ANDROID_HOME": str(SDK)},
    )
    if result.returncode != 0:
        raise RuntimeError(f"flutter build apk failed:\n{result.stdout[-3000:]}\n{result.stderr[-3000:]}")
    APK_PATH.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(APK_OUTPUT, APK_PATH)
    return APK_PATH


def running_emulator():
    """The serial of a running emulator (e.g. "emulator-5554"), or None."""
    result = subprocess.run([ADB, "devices"], capture_output=True, text=True, check=True)
    for line in result.stdout.splitlines()[1:]:
        serial, _, state = line.partition("\t")
        if serial.startswith("emulator-") and state.strip() == "device":
            return serial
    return None


def start_emulator(avd, timeout=240):
    """Boots the named Android Virtual Device and returns (serial, process) once Android has started.
    -no-snapshot-save leaves the AVD's saved state as it was, so test runs don't change it."""
    available = subprocess.run([EMULATOR, "-list-avds"], capture_output=True, text=True).stdout.split()
    if avd not in available:
        raise RuntimeError(f"No Android emulator named {avd!r} (found: {', '.join(available) or 'none'}). "
                           f"Create one in Android Studio › Device Manager.")
    process = subprocess.Popen([EMULATOR, "-avd", avd, "-no-snapshot-save", "-no-boot-anim"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"The {avd} emulator exited while starting.")
        serial = running_emulator()
        if serial:
            booted = subprocess.run([ADB, "-s", serial, "shell", "getprop", "sys.boot_completed"],
                                    capture_output=True, text=True).stdout.strip()
            if booted == "1":
                return serial, process
        time.sleep(2)   # polling the emulator's start-up, not inside a test
    process.terminate()
    raise RuntimeError(f"The {avd} emulator did not finish starting within {timeout}s.")


def uninstall(serial):
    """Removes the app and its saved sign-in, so each test starts from a fresh install."""
    subprocess.run([ADB, "-s", serial, "uninstall", APP_PACKAGE], capture_output=True)
