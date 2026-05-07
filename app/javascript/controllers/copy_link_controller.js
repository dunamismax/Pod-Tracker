import { Controller } from "@hotwired/stimulus"

// Copies a URL to the clipboard and briefly flashes the trigger button label.
// Used by the public deck/pod share pages to put a one-click copy on the link.
export default class extends Controller {
  static targets = ["button"]
  static values = { url: String }

  connect() {
    this.originalLabel = null
    this.timer = null
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  async copy(event) {
    event.preventDefault()
    const url = this.urlValue || window.location.href
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(url)
      } else {
        const ta = document.createElement("textarea")
        ta.value = url
        ta.setAttribute("readonly", "")
        ta.style.position = "absolute"
        ta.style.left = "-9999px"
        document.body.appendChild(ta)
        ta.select()
        document.execCommand("copy")
        document.body.removeChild(ta)
      }
      this.flash("Copied!")
    } catch (_) {
      this.flash("Copy failed")
    }
  }

  flash(label) {
    if (!this.hasButtonTarget) return
    if (this.originalLabel === null) this.originalLabel = this.buttonTarget.textContent
    this.buttonTarget.textContent = label
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      if (this.originalLabel !== null) this.buttonTarget.textContent = this.originalLabel
      this.originalLabel = null
      this.timer = null
    }, 1800)
  }
}
