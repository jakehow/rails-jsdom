import { Controller } from "@hotwired/stimulus"

const imports = {
  package: () => import("lazy-package"),
  url: () => import("https://cdn.example.test/remote.js")
}

export default class extends Controller {
  connect() {
    imports[this.element.dataset.module]().then(module => { this.element.textContent = module.default }, () => { this.element.textContent = "not loaded" })
  }
}
