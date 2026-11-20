"""The real Android app on the emulator (Appium), against the test server. Run with
`pytest --run-device -k android`; add `--slowmo 1000` to pause a second after each step so you can watch it."""

import datetime
import time

import pytest

from tests.support.regulations import find_subsection, get_sections

PREFLIGHT = "91.103 — Preflight action"


def wait_for_saved(api, reference, timeout=10):
    """Polls the API until the item is covered; returns the last copy seen. The app saves right away."""
    deadline = time.monotonic() + timeout
    while True:
        item = find_subsection(get_sections(api, "91"), reference)
        if item["covered"] or time.monotonic() > deadline:
            return item
        time.sleep(0.25)   # polling the server's state, not waiting for time to pass


@pytest.mark.mobile("android")
def test_tc_023_on_the_android_app_a_covered_item_is_saved_and_the_sign_in_survives_a_relaunch(android, api, fresh_user):
    android.sign_in(fresh_user["username"], fresh_user["password"])
    android.wait_for_tracker()
    android.tap(android.section_toggle(PREFLIGHT))
    covered = android.covered_switch("91.103(a)")
    assert covered.get_attribute("checked") == "false"   # control: starts uncovered

    android.tap(covered)

    assert android.wait_for_checked(covered, "true") == "true"
    saved = wait_for_saved(api, "91.103(a)")
    assert saved["covered"] is True
    # The emulator uses the Mac's clock and time zone by default.
    assert saved["date"] == datetime.date.today().isoformat()

    android.relaunch()

    android.wait_for_tracker()   # still signed in: no sign-in screen after the relaunch
    android.tap(android.section_toggle(PREFLIGHT))
    assert android.wait_for_checked(android.covered_switch("91.103(a)"), "true") == "true"
