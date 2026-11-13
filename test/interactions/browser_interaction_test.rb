require "test_helper"

class BrowserInteractionTest < RailsJsdom::TestCase
  test "controllers register on the app's own Stimulus application, one per task in the order of their files, after tasks the page queued" do
    mount_html "<script>setTimeout(() => { window.queuedReady = true }, 0)</script><div id='both' data-controller='beta alpha'></div>"

    assert_equal [ "alpha beta", "true", true ], [ find("#both")["data-log"], find("#both")["data-queued"], evaluate_script("window.Stimulus === window.appStimulus") ]
  end

  test "local and session storage last across full page loads in a session, and not into another session" do
    visit root_path
    execute_script("localStorage.setItem('draft', 'Hello'); sessionStorage.setItem('tab', '1')")
    visit second_path
    kept = evaluate_script("[localStorage.getItem('draft'), sessionStorage.getItem('tab')]")
    other = using_session(:other) do
      visit second_path
      evaluate_script("[localStorage.getItem('draft'), sessionStorage.getItem('tab')]")
    end

    assert_equal [ %w[Hello 1], [ nil, nil ] ], [ kept, other ]
  end

  test "typing into a contenteditable inserts at the caret with the standard input types" do
    visit forms_path
    execute_script("window.types = []; document.getElementById('editor').addEventListener('beforeinput', event => types.push(event.inputType))")
    find("#editor").send_keys("Hi", :enter, "xy", :backspace)

    assert_equal [ "Hi<br>x", %w[insertText insertText insertParagraph insertText insertText deleteContentBackward] ], [ evaluate_script("document.getElementById('editor').innerHTML"), evaluate_script("types") ]
  end

  test "a form-associated custom element's value is submitted with its form through Turbo" do
    add_rating_form(turbo: true)
    click_on "Rate"

    assert_dom "#params", text: { stars: "5" }.to_json
  end

  test "a form-associated custom element's value is submitted with its form without Turbo" do
    add_rating_form(turbo: false)
    click_on "Rate"

    assert_dom "#params", text: { stars: "5" }.to_json
  end

  test "the Fullscreen API behaves as on a desktop browser" do
    mount_html "<p id='shown'>Shown</p>"

    assert_equal [ true, true, true ], evaluate_script(<<~JS)
      new Promise(resolve => {
        const shown = document.getElementById("shown")
        document.addEventListener("fullscreenchange", () => resolve([document.fullscreenEnabled, document.fullscreenElement === shown, true]))
        shown.requestFullscreen()
      })
    JS
  end

  test "a test can dispatch a paste carrying clipboard data, as in system tests" do
    mount_html "<div id='target'></div>"

    assert_equal "Pasted", evaluate_script(<<~JS)
      new Promise(resolve => {
        const target = document.getElementById("target")
        target.addEventListener("paste", event => resolve(event.clipboardData.getData("text/plain")))
        const clipboardData = new DataTransfer()
        clipboardData.setData("text/plain", "Pasted")
        target.dispatchEvent(new ClipboardEvent("paste", { clipboardData, bubbles: true }))
      })
    JS
  end

  test "an XMLHttpRequest sends a Blob body to Rails as its bytes with the Blob's type" do
    mount_html "<p>Upload</p>"

    assert_equal({ "body" => "chunk", "type" => "text/plain" }, evaluate_script(<<~JS))
      new Promise(resolve => {
        const request = new XMLHttpRequest()
        request.open("PUT", "/body")
        request.onload = () => resolve(JSON.parse(request.responseText))
        request.send(new Blob(["chunk"], { type: "text/plain" }))
      })
    JS
  end

  test "a MessageChannel delivers a message to its other port" do
    mount_html "<p>Channel</p>"

    assert_equal "ping", evaluate_script("new Promise(resolve => { const channel = new MessageChannel(); channel.port1.onmessage = event => resolve(event.data); channel.port2.postMessage('ping') })")
  end

  test "checkVisibility is false for an element assertions treat as hidden" do
    mount_html "<p id='shown'>Shown</p><p id='hidden' hidden>Hidden</p>"

    assert_equal [ true, false ], evaluate_script("['shown', 'hidden'].map(id => document.getElementById(id).checkVisibility())")
  end

  test "click_on finds a button by its name" do
    add_to_page "<div id='probe'><form action='/echo'><button name='commit' value='stored'>Store</button></form></div>"
    within("#probe") { click_on "commit" }

    assert_current_path "/echo?commit=stored"
  end

  test "click_on without a locator clicks the only button in scope" do
    add_to_page "<div id='probe'><form action='/echo'><button name='pressed' value='yes'>Press</button></form></div>"
    within("#probe") { click_on }

    assert_current_path "/echo?pressed=yes"
  end

  test "click_link without a locator clicks the only link in scope" do
    add_to_page "<div id='probe'><a href='/second'>Go</a></div>"
    within("#probe") { click_link }

    assert_current_path "/second"
  end

  test "first without a selector filters any element by class, excluding a class with !" do
    mount_html "<p class='note'>Plain</p><span class='note urgent'>Urgent</span><em class='note'>Last</em>"

    assert_equal [ "Plain", "Urgent", %w[Plain Last] ], [ first(class: "note").text, first(class: %w[note urgent]).text, all(class: %w[note !urgent]).map(&:text) ]
  end

  private

  def add_to_page(html)
    visit forms_path
    execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", html)
  end

  def add_rating_form(turbo:)
    visit forms_path
    execute_script(<<~JS)
      customElements.define("star-rating", class extends HTMLElement {
        static formAssociated = true
        constructor() { super(); this.internals = this.attachInternals() }
        connectedCallback() { this.internals.setFormValue("5") }
      })
    JS
    execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", %(<form action="/echo" method="get" data-turbo="#{turbo}"><star-rating name="stars"></star-rating><button>Rate</button></form>))
  end
end
