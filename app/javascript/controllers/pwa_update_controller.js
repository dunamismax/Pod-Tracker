import { Controller } from "@hotwired/stimulus"

// Registers /service-worker.js and surfaces an update banner when a newer
// service worker is waiting. Clicking "Reload" tells the waiting worker to
// skip waiting; the controllerchange listener then reloads the page so the
// user is not trapped on stale assets.
export default class extends Controller {
  static targets = ["banner"]
  static values = { clearPageCache: Boolean }

  connect() {
    if (!("serviceWorker" in navigator)) return
    if (window.location.protocol !== "https:" && window.location.hostname !== "localhost") return

    this.reloading = false
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (this.reloading) return
      this.reloading = true
      window.location.reload()
    })

    navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
      .then((registration) => {
        this.registration = registration
        if (registration.waiting && navigator.serviceWorker.controller) {
          this.showBanner()
        }
        registration.addEventListener("updatefound", () => {
          const installing = registration.installing
          if (!installing) return
          installing.addEventListener("statechange", () => {
            if (installing.state === "installed" && navigator.serviceWorker.controller) {
              this.showBanner()
            }
          })
        })
      })
      .catch(() => { /* registration failed; offline cache is best-effort */ })

    if (this.clearPageCacheValue) this.clearPageCaches()
  }

  showBanner() {
    if (!this.hasBannerTarget) return
    this.bannerTarget.hidden = false
  }

  reload(event) {
    event.preventDefault()
    const waiting = this.registration && this.registration.waiting
    if (waiting) {
      waiting.postMessage({ type: "SKIP_WAITING" })
    } else {
      window.location.reload()
    }
  }

  dismiss(event) {
    event.preventDefault()
    if (this.hasBannerTarget) this.bannerTarget.hidden = true
  }

  clearPageCaches() {
    if ("caches" in window) {
      caches.keys()
        .then((names) => Promise.all(names
          .filter((name) => name.startsWith("pod-tracker-pages-"))
          .map((name) => caches.delete(name))))
        .catch(() => {})
    }

    if (navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({ type: "CLEAR_PAGE_CACHE" })
    } else {
      navigator.serviceWorker.ready
        .then((registration) => {
          if (registration.active) registration.active.postMessage({ type: "CLEAR_PAGE_CACHE" })
        })
        .catch(() => {})
    }
  }
}
