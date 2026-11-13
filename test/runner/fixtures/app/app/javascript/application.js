import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import greeting from "lib/greeting"
import "lib"

window.Current = { greeting: greeting("the app entry") }
window.AppStimulus = Application.start()
window.Stimulus = window.AppStimulus
eagerLoadControllersFrom("controllers", window.AppStimulus)
