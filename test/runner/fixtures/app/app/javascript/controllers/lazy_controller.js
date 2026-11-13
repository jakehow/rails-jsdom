import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    import("not-pinned").then(() => { this.element.textContent = "loaded" }, () => { this.element.textContent = "not loaded" })
  }
}
