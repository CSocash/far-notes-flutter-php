"""Device tests: the real Flutter app on the iOS Simulator and the Android emulator, driven by Appium.
They run only with `pytest --run-device`; add `-k ios` or `-k android` for one platform.

iOS needs Xcode, the XCUITest driver (`appium driver install xcuitest`) and the iPhone 17 simulator.
Android needs Android Studio's SDK, the UiAutomator2 driver (`appium driver install uiautomator2`) and the
Pixel_10_Pro emulator, which is started here unless an emulator is already running.
Appium is started here if nothing is listening on APPIUM_URL. Each app is rebuilt once per session against
the shared test server (port 3100), never the dev server on port 3000.
"""

import json
import os
import subprocess
import time
import urllib.request

import pytest
from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.options.ios import XCUITestOptions

from tests.pages.android_app import AndroidApp
from tests.pages.ios_app import IosApp
from tests.support import android_app
from tests.support.ios_app import BUNDLE_ID, build_ios_app, simulator_udid

APPIUM_URL = "http://127.0.0.1:4723"
SIMULATOR = "iPhone 17"   # not the simulator Xcode runs the app on, so a test run doesn't replace that copy
ANDROID_AVD = "Pixel_10_Pro"


def _appium_is_up():
    try:
        with urllib.request.urlopen(f"{APPIUM_URL}/status", timeout=1) as res:
            return json.load(res)["value"]["ready"]
    except OSError:
        return False


@pytest.fixture(scope="session")
def appium_server():
    if _appium_is_up():
        yield APPIUM_URL
        return
    # --address keeps Appium on this Mac; by default it listens on every network address, without a password.
    # The UiAutomator2 driver finds adb through ANDROID_HOME, which a Mac doesn't set unless you add it yourself.
    process = subprocess.Popen(["appium", "--address", "127.0.0.1", "--port", APPIUM_URL.rsplit(":", 1)[1],
                                "--log-level", "warn"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               env={**os.environ, "ANDROID_HOME": str(android_app.SDK)})
    deadline = time.monotonic() + 30
    while not _appium_is_up():
        if process.poll() is not None or time.monotonic() > deadline:
            process.kill()
            raise RuntimeError("Appium did not start. Is it installed (`npm install -g appium`)?")
        time.sleep(0.2)   # polling start-up, not inside a test
    yield APPIUM_URL
    process.terminate()


@pytest.fixture(scope="session")
def ios_simulator():
    return simulator_udid(SIMULATOR)


@pytest.fixture(scope="session")
def ios_app_path(test_server, ios_simulator):
    return build_ios_app(test_server, ios_simulator)


@pytest.fixture
def ios_app(request, appium_server, ios_simulator, ios_app_path):
    """A fresh install of the app (no saved sign-in), wrapped in the IosApp screen object."""
    subprocess.run(["xcrun", "simctl", "uninstall", ios_simulator, BUNDLE_ID], capture_output=True)
    options = XCUITestOptions()
    options.udid = ios_simulator
    options.app = str(ios_app_path)
    options.bundle_id = BUNDLE_ID
    options.set_capability("appium:wdaLaunchTimeout", 240_000)   # the first run builds WebDriverAgent
    driver = webdriver.Remote(appium_server, options=options)
    app = IosApp(driver, slowmo_ms=float(request.config.getoption("slowmo") or 0))
    yield app
    app.pause()   # in slow mode, leave the final screen up for a moment
    driver.quit()


@pytest.fixture(scope="session")
def android_emulator():
    """The serial of a running emulator. One already running is reused and left running; otherwise
    ANDROID_AVD is started for the session and shut down afterwards."""
    serial = android_app.running_emulator()
    if serial:
        yield serial
        return
    serial, process = android_app.start_emulator(ANDROID_AVD)
    yield serial
    subprocess.run([android_app.ADB, "-s", serial, "emu", "kill"], capture_output=True)
    process.wait(timeout=60)


@pytest.fixture(scope="session")
def android_apk_path(test_server):
    return android_app.build_android_app(test_server)


@pytest.fixture
def android(request, appium_server, android_emulator, android_apk_path):
    """A fresh install of the Android app (no saved sign-in), wrapped in the AndroidApp screen object."""
    android_app.uninstall(android_emulator)
    options = UiAutomator2Options()
    options.udid = android_emulator
    options.app = str(android_apk_path)
    options.app_package = android_app.APP_PACKAGE
    options.set_capability("appium:uiautomator2ServerInstallTimeout", 120_000)   # first run installs the server
    driver = webdriver.Remote(appium_server, options=options)
    app = AndroidApp(driver, slowmo_ms=float(request.config.getoption("slowmo") or 0))
    yield app
    app.pause()
    driver.quit()
