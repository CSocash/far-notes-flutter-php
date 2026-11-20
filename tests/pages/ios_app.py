"""The iOS app's screens for Appium, found by the accessibility labels VoiceOver reads.

The Flutter app gives its widgets the same accessible names as the website, so these match the names the
Playwright page objects use: "Mark 91.103(a) as covered" is a switch, "Sign in" a button, and so on.
"""

import time

from appium.webdriver.common.appiumby import AppiumBy
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.support.ui import WebDriverWait

from tests.support.ios_app import BUNDLE_ID


class IosApp:
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
        element.send_keys(text)
        self.pause()

    def element(self, kind, label):
        """An element by its type and accessibility label, e.g. ("Button", "Sign in")."""
        predicate = f"type == 'XCUIElementType{kind}' AND label == '{label}'"
        return WebDriverWait(self.driver, self.timeout).until(
            lambda driver: driver.find_element(AppiumBy.IOS_PREDICATE, predicate)
        )

    def scroll_to(self, kind, label, max_scrolls=20):
        """An element in the tracker's list, scrolled into the upper part of the screen and at rest.

        Flutter builds only the list rows on or near the screen, so a row further down isn't in the
        accessibility tree at all until it has been scrolled to (a web view exposes the whole page).
        The row must also have stopped moving: on iOS a tap on a list that is still scrolling only stops
        the scroll, and the bottom of the screen is covered by the Add section button."""
        predicate = f"type == 'XCUIElementType{kind}' AND label == '{label}' AND visible == 1"
        size = self.driver.get_window_size()
        x = size["width"] / 2
        for _ in range(max_scrolls):
            element = self._at_rest(predicate)
            if element is not None and element.rect["y"] + element.rect["height"] / 2 < size["height"] * 0.7:
                return element
            # A slow drag up by a third of the screen: scrolls without flinging past the row.
            self.driver.execute_script("mobile: dragFromToForDuration", {
                "fromX": x, "fromY": size["height"] * 0.7, "toX": x, "toY": size["height"] * 0.37, "duration": 0.6,
            })
        raise TimeoutException(f"No visible {kind} labelled {label!r} after {max_scrolls} scrolls")

    def _at_rest(self, predicate, checks=10):
        """The first element matching predicate once its position stops changing, or None if there is none."""
        last = None
        for _ in range(checks):
            found = self.driver.find_elements(AppiumBy.IOS_PREDICATE, predicate)
            if not found:
                return None
            if found[0].rect == last:
                return found[0]
            last = found[0].rect
            time.sleep(0.15)   # polling the list until scrolling stops, not waiting for time to pass
        return found[0]

    def text_field(self, label):
        """A text box by its label. Flutter reports a password box as a plain TextField (the text is still
        hidden on screen), where a web view reports a SecureTextField, so either type matches."""
        predicate = f"type IN {{'XCUIElementTypeTextField', 'XCUIElementTypeSecureTextField'}} AND label == '{label}'"
        return WebDriverWait(self.driver, self.timeout).until(
            lambda driver: driver.find_element(AppiumBy.IOS_PREDICATE, predicate)
        )

    def wait_for_value(self, element, value):
        """Waits for an element's accessibility value, e.g. a switch turning "1"; returns the last value seen."""
        try:
            WebDriverWait(self.driver, self.timeout).until(lambda _: element.get_attribute("value") == value)
        except TimeoutException:
            pass   # the test's assertion reports the value it got
        return element.get_attribute("value")

    # Sign-in screen
    def sign_in(self, username, password):
        self.type_into(self.text_field("Username or email"), username)
        self.type_into(self.text_field("Password"), password)
        self.tap(self.element("Button", "Sign in"))

    # Tracker
    def wait_for_tracker(self):
        status = self.element("StaticText", "Connected to SQLite")
        self.pause()
        return status

    def section_toggle(self, heading):
        return self.scroll_to("Button", f"Study items in {heading}")

    def covered_switch(self, reference):
        """The covered switch, for reading its value ("0" or "1")."""
        return self.scroll_to("Switch", f"Mark {reference} as covered")

    def covered_control(self, reference):
        """What a person taps to mark an item covered: the switch itself."""
        return self.covered_switch(reference)

    def relaunch(self):
        """Quits the app and opens it again, like swiping it away and tapping its icon."""
        self.driver.terminate_app(BUNDLE_ID)
        self.pause()
        self.driver.activate_app(BUNDLE_ID)
        self.pause()
