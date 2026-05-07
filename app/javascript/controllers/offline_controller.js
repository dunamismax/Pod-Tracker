import { Controller } from "@hotwired/stimulus"

// Surfaces an honest connection status:
//   - shows the offline banner whenever the browser reports `navigator.onLine`
//     is false. We never claim a write reached the server while disconnected.
//   - tags the document with `data-offline="true"` and disables submit buttons
//     inside `[data-offline-disable]` forms so import/save/AI-evaluation
//     submissions are paused with a clear "Reconnect to submit" hint instead
//     of optimistic UI that pretends the server accepted the request.
export default class extends Controller {
  static targets = ["banner"]

  connect() {
    this.handleOnline = this.handleOnline.bind(this)
    this.handleOffline = this.handleOffline.bind(this)
    window.addEventListener("online", this.handleOnline)
    window.addEventListener("offline", this.handleOffline)
    this.refresh()
  }

  disconnect() {
    window.removeEventListener("online", this.handleOnline)
    window.removeEventListener("offline", this.handleOffline)
  }

  handleOnline() {
    this.refresh()
  }

  handleOffline() {
    this.refresh()
  }

  refresh() {
    const offline = !navigator.onLine
    document.documentElement.dataset.offline = offline ? "true" : "false"
    if (this.hasBannerTarget) this.bannerTarget.hidden = !offline
    this.applyFormState(offline)
  }

  applyFormState(offline) {
    const forms = document.querySelectorAll("form[data-offline-disable]")
    forms.forEach((form) => {
      const submits = form.querySelectorAll('button[type="submit"], input[type="submit"]')
      submits.forEach((btn) => {
        if (offline) {
          if (!btn.dataset.offlineOriginal) {
            btn.dataset.offlineOriginal = btn.value || btn.textContent || ""
          }
          btn.disabled = true
          btn.setAttribute("aria-disabled", "true")
          btn.classList.add("cursor-not-allowed", "opacity-60")
          const label = btn.dataset.offlineLabel || "Reconnect to submit"
          if (btn.tagName === "INPUT") {
            btn.value = label
          } else {
            btn.textContent = label
          }
        } else if (btn.dataset.offlineOriginal !== undefined) {
          btn.disabled = false
          btn.removeAttribute("aria-disabled")
          btn.classList.remove("cursor-not-allowed", "opacity-60")
          if (btn.tagName === "INPUT") {
            btn.value = btn.dataset.offlineOriginal
          } else {
            btn.textContent = btn.dataset.offlineOriginal
          }
          delete btn.dataset.offlineOriginal
        }
      })
    })
  }
}
