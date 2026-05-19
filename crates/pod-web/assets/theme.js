(function () {
  "use strict";

  var STORAGE_KEY = "pod-tracker-theme";
  var root = document.documentElement;

  function readStored() {
    try {
      return window.localStorage.getItem(STORAGE_KEY);
    } catch (_) {
      return null;
    }
  }

  function writeStored(value) {
    try {
      window.localStorage.setItem(STORAGE_KEY, value);
    } catch (_) {
      /* ignore quota / unavailable storage */
    }
  }

  function resolveInitial() {
    var stored = readStored();
    if (stored === "light" || stored === "dark") {
      return stored;
    }
    return "dark";
  }

  function apply(theme) {
    root.setAttribute("data-theme", theme);
    var buttons = document.querySelectorAll("[data-theme-toggle]");
    for (var i = 0; i < buttons.length; i++) {
      var next = theme === "dark" ? "light" : "dark";
      buttons[i].setAttribute("aria-pressed", theme === "dark" ? "false" : "true");
      buttons[i].setAttribute(
        "aria-label",
        "Switch to " + next + " theme"
      );
      buttons[i].setAttribute("title", "Switch to " + next + " theme");
    }
  }

  apply(resolveInitial());

  function wire() {
    var buttons = document.querySelectorAll("[data-theme-toggle]");
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener("click", function () {
        var current = root.getAttribute("data-theme") === "light" ? "light" : "dark";
        var next = current === "dark" ? "light" : "dark";
        apply(next);
        writeStored(next);
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", wire);
  } else {
    wire();
  }
})();
