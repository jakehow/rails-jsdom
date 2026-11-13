import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.dataset.log = `${this.element.dataset.log || ""} beta`.trim()
  }
}
