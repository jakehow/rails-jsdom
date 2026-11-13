import { Application } from "@hotwired/stimulus"

const application = Application.start()
window.Stimulus = application
window.appStimulus = application

export { application }
