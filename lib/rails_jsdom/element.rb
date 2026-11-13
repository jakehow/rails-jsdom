module RailsJsdom
  # An element on the page, returned by TestHelper#find, TestHelper#all,
  # TestHelper#first, TestHelper#find_field, TestHelper#find_button and
  # TestHelper#find_link.
  #
  # An element refers to a node in the live page. Actions on it settle the
  # page like the TestHelper actions. Once the node leaves the page, for
  # example after a navigation, using the element raises RailsJsdom::Error.
  #
  #   item = find("#cart li", text: "Mug")
  #   item.find_button("Remove").click
  #   assert_equal "2", find_field("Quantity").value
  class Element
    def self.action(name) # :nodoc:
      define_method(name) { perform(name) }
    end

    def self.read(name, from: name.to_s.delete_suffix("?")) # :nodoc:
      define_method(name) { description.fetch(from) }
    end

    def self.scoped_helper(name) # :nodoc:
      define_method(name) do |*arguments, **options|
        @test.within(self) { @test.public_send(name, *arguments, **options) }
      end
    end

    private_class_method :action, :read, :scoped_helper

    attr_reader :handle # :nodoc:

    def initialize(test, handle) # :nodoc:
      @test = test
      @handle = handle
    end

    # Runs `script` in the page with `this` set to the element, as in system
    # tests. Extra arguments are available as `arguments`.
    def execute_script(script, *arguments)
      @test.rails_jsdom_script(script, arguments, "statements", handle)
      nil
    end

    # Evaluates `script` with `this` set to the element and returns its value.
    def evaluate_script(script, *arguments)
      @test.rails_jsdom_script(script, arguments, "expression", handle)
    end

    ##
    # Clicks the element.
    action :click

    ##
    # Moves the pointer over the element. See TestHelper#hover.
    action :hover

    ##
    # Double-clicks the element. See TestHelper#double_click.
    action :double_click

    ##
    # Right-clicks the element. See TestHelper#right_click.
    action :right_click

    ##
    # Selects this `option` in its select.
    action :select_option

    ##
    # Deselects this `option` in a select that allows multiple options.
    action :unselect_option

    # Sets the element's value: text for a text-like field or a
    # `contenteditable` element, `true` or `false` for a checkbox, `true` to
    # select a radio button.
    def set(value)
      perform(:set, value: value)
    end

    # Focuses the element and types `keys` into it. See TestHelper#send_keys.
    def send_keys(*keys)
      perform(:send_keys, keys: RailsJsdom.keys(keys))
    end

    ##
    # The visible text of the element.
    read :text

    ##
    # The current value of a field, or `nil` for an element without one.
    read :value

    ##
    # The element's tag name, such as `"button"`.
    read :tag_name, from: "tag"

    ##
    # Whether a checkbox or radio button is checked.
    read :checked?

    ##
    # Whether an `option` is selected.
    read :selected?

    ##
    # Whether the element is disabled.
    read :disabled?

    ##
    # Whether the element is visible: neither it nor an ancestor is hidden.
    read :visible?

    # The value of the attribute `name`, or the current value for `:value`.
    def [](name)
      name.to_s == "value" ? value : description.fetch("attributes")[name.to_s]
    end

    ##
    # Like TestHelper#find, searching inside this element.
    scoped_helper :find

    ##
    # Like TestHelper#all, searching inside this element.
    scoped_helper :all

    ##
    # Like TestHelper#first, searching inside this element.
    scoped_helper :first

    ##
    # Like TestHelper#find_field, searching inside this element.
    scoped_helper :find_field

    ##
    # Like TestHelper#find_button, searching inside this element.
    scoped_helper :find_button

    ##
    # Like TestHelper#find_link, searching inside this element.
    scoped_helper :find_link

    ##
    # Like TestHelper#assert_text, for the text inside this element.
    scoped_helper :assert_text

    ##
    # Like TestHelper#assert_no_text, for the text inside this element.
    scoped_helper :assert_no_text

    ##
    # Like TestHelper#assert_selector, inside this element.
    scoped_helper :assert_selector

    ##
    # Like TestHelper#assert_no_selector, inside this element.
    scoped_helper :assert_no_selector

    ##
    # Like TestHelper#has_text?, for the text inside this element.
    scoped_helper :has_text?

    ##
    # Like TestHelper#has_no_text?, for the text inside this element.
    scoped_helper :has_no_text?

    ##
    # Like TestHelper#has_selector?, inside this element.
    scoped_helper :has_selector?

    ##
    # Like TestHelper#has_no_selector?, inside this element.
    scoped_helper :has_no_selector?

    # Two elements are equal when they refer to the same node.
    def ==(other)
      other.is_a?(Element) && other.handle == handle
    end
    alias_method :eql?, :==

    def hash # :nodoc:
      handle.hash
    end

    def inspect # :nodoc:
      "#<RailsJsdom::Element #{handle}>"
    end

    private

    def perform(action, **options)
      @test.rails_jsdom_element(handle, action.to_s, **options)
    end

    def description
      @test.rails_jsdom_read(handle)
    end
  end
end
