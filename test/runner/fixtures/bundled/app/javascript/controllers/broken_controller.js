import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    throw new Error("broken controller")
  }
}
