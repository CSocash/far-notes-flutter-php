// The one place page scripts make requests and change pages, so every page does both the same way:
// same-origin fetch with the session cookie, and clean URLs like /login.
// (It once also served the Capacitor app; the Flutter app in app/ calls the server itself.)
(function () {
  function apiFetch(path, init = {}) {
    return fetch(path, init);
  }

  function goTo(page) {
    window.location.replace(page);
  }

  window.FarNotesApi = { fetch: apiFetch, goTo };
})();
