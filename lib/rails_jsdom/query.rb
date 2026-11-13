module RailsJsdom
  class Query # :nodoc:
    DISABLED_BY_DEFAULT = %w[field button].freeze

    attr_reader :strategy, :locator

    def self.like?(actual, expected)
      expected.is_a?(Regexp) ? actual.match?(expected) : actual.include?(expected.to_s)
    end

    def self.flag?(actual, expected)
      expected == :all || actual == expected
    end

    def self.classes?(actual, expected)
      expected.all? { |name| class_matches?(actual, name) }
    end

    def self.class_matches?(actual, name)
      name.start_with?("!") ? actual.exclude?(name.delete_prefix("!")) : actual.include?(name)
    end

    def self.same?(actual, expected)
      expected.is_a?(Regexp) ? actual.match?(expected) : actual == expected.to_s
    end

    def initialize(strategy, locator, text: nil, exact_text: nil, visible: true, with: nil, checked: nil, unchecked: nil, disabled: nil, href: nil, type: nil, id: nil, **others)
      classes = others.delete(:class)
      RailsJsdom.reject_options(others.keys)
      @strategy = strategy
      @locator = locator
      @visible = visible
      disabled = false if disabled.nil? && DISABLED_BY_DEFAULT.include?(strategy)
      @filters = { text: text, exact_text: exact_text, with: with, checked: checked, unchecked: unchecked, disabled: disabled, href: href, type: type, id: id, class: classes && Array(classes) }.compact
    end

    def message
      { command: "query", strategy: strategy, locator: locator }
    end

    def filter(descriptors)
      descriptors.select { |descriptor| visible?(descriptor) && matches?(comparable_values(descriptor)) }
    end

    def description
      [ "#{strategy} #{locator.inspect}", *@filters.map { |name, expected| "#{name}: #{expected.inspect}" } ].join(", ")
    end

    private

    def visible?(descriptor)
      case @visible
      when true
        descriptor.fetch("visible")
      when :hidden
        !descriptor.fetch("visible")
      else
        true
      end
    end

    def matches?(values)
      @filters.all? { |name, expected| satisfies?(name, expected, values.fetch(name)) }
    end

    def satisfies?(name, expected, actual)
      case name
      when :text
        Query.like?(actual, expected)
      when :checked, :unchecked, :disabled
        Query.flag?(actual, expected)
      when :class
        Query.classes?(actual, expected)
      else
        Query.same?(actual, expected)
      end
    end

    def comparable_values(descriptor)
      {
        text: descriptor.fetch(@visible == true ? "text" : "all_text"),
        exact_text: descriptor.fetch("text"),
        with: descriptor.fetch("value").to_s,
        checked: descriptor.fetch("checked"),
        unchecked: !descriptor.fetch("checked"),
        disabled: descriptor.fetch("disabled"),
        type: descriptor.fetch("type")
      }.merge(attribute_values(descriptor.fetch("attributes")))
    end

    def attribute_values(attributes)
      { href: attributes["href"].to_s, id: attributes["id"].to_s, class: attributes["class"].to_s.split }
    end
  end
end
