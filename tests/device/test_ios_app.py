"""The real iOS app in the Simulator (Appium), against the test server. Run with `pytest --run-device`;
add `--slowmo 1000` to pause a second after each step so you can watch it.

Fixtures used (they run before the test, so it starts ready to go):
- `ios_app`: the Flutter app freshly installed on the iPhone 17 Simulator and opened, wrapped in the
  IosApp page object (tests/pages/ios_app.py), which finds elements by their accessibility labels.
- `fresh_user`: a brand-new account on the test server, so no earlier test's data can affect this one.
- `api`: an HTTP client signed in as that same user. The test uses it to check the server, not just the screen.
"""

import datetime
import time

import pytest

from tests.support.regulations import find_subsection, get_sections

# The section heading exactly as the app shows it. 91.103 is a locked starter section, so every
# fresh user has it, and its first study item is 91.103(a).
PREFLIGHT = "91.103 — Preflight action"


def wait_for_saved(api, reference, timeout=10):
    """Polls the API until the item is covered; returns the last copy seen.
    The app saves a switch tap right away, but the request still takes a moment to reach the server."""
    deadline = time.monotonic() + timeout
    while True:
        item = find_subsection(get_sections(api, "91"), reference)
        # Stop as soon as it's saved, or after the timeout. Either way, return what the server has,
        # so a failing assertion in the test shows the real saved values.
        if item["covered"] or time.monotonic() > deadline:
            return item
        time.sleep(0.25)   # polling the server's state, not waiting for time to pass


@pytest.mark.mobile("ios")
def test_tc_022_on_the_ios_app_a_covered_item_is_saved_and_the_sign_in_survives_a_relaunch(ios_app, api, fresh_user):
    # Sign in through the app's own sign-in screen, then wait for the tracker to finish loading
    # ("Connected to SQLite" appears once the regulations have arrived from the server).
    ios_app.sign_in(fresh_user["username"], fresh_user["password"])
    ios_app.wait_for_tracker()

    # Open the PREFLIGHT section. Sections start collapsed, so their study items aren't on screen yet.
    ios_app.tap(ios_app.section_toggle(PREFLIGHT))
    covered = ios_app.covered_switch("91.103(a)")
    # Control check: the switch must start off. Otherwise the "1" asserted below would prove nothing.
    # On iOS a switch's accessibility value is "0" (off) or "1" (on).
    assert covered.get_attribute("value") == "0"

    # The action under test: a person taps the switch.
    ios_app.tap(ios_app.covered_control("91.103(a)"))

    # 1. The screen shows it: the switch turns on.
    assert ios_app.wait_for_value(covered, "1") == "1"
    # 2. The server saved it: covered, and dated today (the app fills in today's date when it's marked).
    saved = wait_for_saved(api, "91.103(a)")
    assert saved["covered"] is True
    # The Simulator uses the Mac's clock and time zone, which can't be fixed from here.
    assert saved["date"] == datetime.date.today().isoformat()

    # Quit the app and open it again, like swiping it away and tapping its icon.
    ios_app.relaunch()

    # 3. The sign-in was remembered: the tracker loads with no sign-in screen in between.
    ios_app.wait_for_tracker()
    # 4. The saved item comes back from the server: after reopening the section, the switch is still on.
    ios_app.tap(ios_app.section_toggle(PREFLIGHT))
    assert ios_app.wait_for_value(ios_app.covered_switch("91.103(a)"), "1") == "1"
