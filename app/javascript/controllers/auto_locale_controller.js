import { Controller } from "@hotwired/stimulus"

// Fills hidden timezone and unit-preference inputs on the registration form
// so the user does not have to pick them by hand. Timezone comes from the
// browser's resolved IANA zone; units are guessed from navigator.language
// (US/Liberia/Myanmar use imperial, everywhere else metric). The server
// re-validates and falls back to UTC + imperial if either value is missing
// or unknown, so a JS-disabled or weird-locale browser still creates an
// account cleanly.
export default class extends Controller {
  static targets = ["timezone", "units"]

  connect() {
    this.fillTimezone()
    this.fillUnits()
  }

  fillTimezone() {
    if (!this.hasTimezoneTarget) return
    try {
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (tz) this.timezoneTarget.value = tz
    } catch (_) {
      // leave blank — the server will default to UTC
    }
  }

  fillUnits() {
    if (!this.hasUnitsTarget) return
    try {
      const lang = (navigator.language || "").toLowerCase()
      const imperial = /^en-us\b/.test(lang) || /^en-lr\b/.test(lang) || /^my-mm\b/.test(lang)
      this.unitsTarget.value = imperial ? "imperial" : "metric"
    } catch (_) {
      this.unitsTarget.value = "imperial"
    }
  }
}
