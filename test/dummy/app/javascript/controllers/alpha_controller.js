import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.dataset.log = `${this.element.dataset.log || ""} alpha`.trim()
    this.element.dataset.queued = String(Boolean(window.queuedReady))
  }
}
