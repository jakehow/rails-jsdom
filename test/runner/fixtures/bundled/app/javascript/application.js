import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import greeting from "virtual:greeting"
import CounterController from "./controllers/counter_controller"
import BrokenController from "./controllers/broken_controller"
import LazyController from "./controllers/lazy_controller"

window.Current = { greeting, builtBy: BUILT_BY }
const application = Application.start()
application.register("counter", CounterController)
application.register("broken", BrokenController)
application.register("lazy", LazyController)
