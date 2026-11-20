"""Builds the Flutter iOS app for device tests, pointed at the test server instead of the dev server on port 3000.

The server address is compiled in with --dart-define=FAR_NOTES_API_URL. The built app is copied to
.test-data/ios-build, so a later `flutter run` or build in app/ can't swap it out mid-run. A wrong address
shows up quickly: the test's freshly registered user exists only in the test server's database, so
signing in would fail.
"""

import json
import os
import shutil
import subprocess

from tests.support.server import ROOT, TEST_DATA

APP_DIR = ROOT / "app"
BUILD_OUTPUT = APP_DIR / "build/ios/iphonesimulator/Runner.app"
APP_PATH = TEST_DATA / "ios-build/Runner.app"
BUNDLE_ID = "com.farnotes.studylog"
FLUTTER = shutil.which("flutter") or os.path.expanduser("~/development/flutter/bin/flutter")


def build_ios_app(api_url, simulator_udid):
    """Builds Runner.app for the simulator with api_url compiled in, and returns its path."""
    result = subprocess.run(
        [FLUTTER, "build", "ios", "--simulator", "--debug", f"--dart-define=FAR_NOTES_API_URL={api_url}"],
        cwd=APP_DIR, capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"flutter build ios failed:\n{result.stdout[-3000:]}\n{result.stderr[-3000:]}")
    shutil.rmtree(APP_PATH, ignore_errors=True)
    shutil.copytree(BUILD_OUTPUT, APP_PATH, symlinks=True)
    return APP_PATH


def simulator_udid(name):
    """The id of the newest available iOS simulator with this name, e.g. "iPhone 17"."""
    result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True, check=True)
    runtimes = json.loads(result.stdout)["devices"]
    matches = [
        device["udid"]
        for runtime in sorted(runtimes, reverse=True)
        if "iOS" in runtime
        for device in runtimes[runtime]
        if device["name"] == name
    ]
    if not matches:
        raise RuntimeError(f"No available iOS simulator named {name!r}. Add one in Xcode › Window › Devices and Simulators.")
    return matches[0]
