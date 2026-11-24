import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.dataset.connections = Number(this.element.dataset.connections ?? 0) + 1
  }
}
