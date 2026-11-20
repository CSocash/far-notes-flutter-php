"""The Android app's screens for Appium (UiAutomator2), found by the accessibility labels TalkBack reads.

The Flutter app gives its widgets the same accessible names as the website and the iOS app: on Android
they are the content-desc, which Appium finds as an "accessibility id". Text boxes are the exception:
Android shows their label only as a hint, so they carry a test id (resource-id) instead.
"""

import time

from appium.webdriver.common.appiumby import AppiumBy
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.support.ui import WebDriverWait

from tests.support.android_app import APP_PACKAGE


class AndroidApp:
    def __init__(self, driver, timeout=15, slowmo_ms=0):
        self.driver = driver
        self.timeout = timeout
        self.slowmo = slowmo_ms / 1000

    def pause(self):
        """Slow mode (`--slowmo 1000`): a pause after each action, so a person can follow the run."""
        if self.slowmo:
            time.sleep(self.slowmo)

    def tap(self, element):
        element.click()
        self.pause()

    def type_into(self, element, text):
        element.click()
        element.send_keys(text)
        self.pause()

    def _wait_for(self, by, value):
        return WebDriverWait(self.driver, self.timeout).until(lambda driver: driver.find_element(by, value))

    def labelled(self, label):
        """An element by its accessibility label (content-desc), e.g. "Sign in"."""
        return self._wait_for(AppiumBy.ACCESSIBILITY_ID, label)

    def text_field(self, test_id):
        """A text box by its test id (Semantics identifier, shown to Android as resource-id)."""
        return self._wait_for(AppiumBy.ANDROID_UIAUTOMATOR, f'new UiSelector().resourceId("{test_id}")')

    def scroll_to(self, label, max_scrolls=20):
        """An element in the tracker's list, scrolled into the upper part of the screen and at rest.
        Flutter builds only the rows on or near the screen, so rows further down appear only once scrolled to."""
        size = self.driver.get_window_size()
        for _ in range(max_scrolls):
            element = self._at_rest(label)
            if element is not None and element.rect["y"] + element.rect["height"] / 2 < size["height"] * 0.7:
                return element
            self.driver.execute_script("mobile: dragGesture", {
                "startX": size["width"] // 2, "startY": int(size["height"] * 0.7),
                "endX": size["width"] // 2, "endY": int(size["height"] * 0.37), "speed": 1500,
            })
        raise TimeoutException(f"No element labelled {label!r} after {max_scrolls} scrolls")

    def _at_rest(self, label, checks=10):
        """The element with this label once its position stops changing, or None if it isn't on screen."""
        last = None
        for _ in range(checks):
            found = self.driver.find_elements(AppiumBy.ACCESSIBILITY_ID, label)
            if not found:
                return None
            if found[0].rect == last:
                return found[0]
            last = found[0].rect
            time.sleep(0.15)   # polling the list until scrolling stops, not waiting for time to pass
        return found[0]

    def wait_for_checked(self, element, checked):
        """Waits for a switch's checked state ("true"/"false"); returns the last value seen."""
        try:
            WebDriverWait(self.driver, self.timeout).until(lambda _: element.get_attribute("checked") == checked)
        except TimeoutException:
            pass   # the test's assertion reports the value it got
        return element.get_attribute("checked")

    # Sign-in screen
    def sign_in(self, username, password):
        self.type_into(self.text_field("username"), username)
        self.type_into(self.text_field("password"), password)
        self.driver.hide_keyboard()
        self.tap(self.labelled("Sign in"))

    # Tracker
    def wait_for_tracker(self):
        status = self.labelled("Connected to SQLite")
        self.pause()
        return status

    def section_toggle(self, heading):
        return self.scroll_to(f"Study items in {heading}")

    def covered_switch(self, reference):
        return self.scroll_to(f"Mark {reference} as covered")

    def relaunch(self):
        """Closes the app and opens it again, like swiping it away and tapping its icon."""
        self.driver.terminate_app(APP_PACKAGE)
        self.pause()
        self.driver.activate_app(APP_PACKAGE)
        self.pause()
