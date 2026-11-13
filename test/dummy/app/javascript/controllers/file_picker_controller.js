import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview"]

  choose() {
    const input = Object.assign(document.createElement("input"), { type: "file" })
    input.addEventListener("change", () => this.upload(input.files[0]))
    input.click()
  }

  upload(file) {
    const preview = new window.Image()
    preview.addEventListener("load", () => this.previewTarget.replaceChildren(preview))
    preview.src = window.URL.createObjectURL(file)
    const data = new window.FormData()
    data.append("document", file)
    const request = new window.XMLHttpRequest()
    request.open("POST", "/uploads")
    request.setRequestHeader("Accept", "text/vnd.turbo-stream.html")
    request.addEventListener("load", () => window.Turbo.renderStreamMessage(request.responseText))
    request.send(data)
  }
}
