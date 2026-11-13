# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/verb_led_bang_method"

class RuboCop::Cop::Readability::VerbLedBangMethodTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source, cop_config = {})
    config = RuboCop::Config.new("Readability/VerbLedBangMethod" => { "Enabled" => true }.merge(cop_config))
    cop = RuboCop::Cop::Readability::VerbLedBangMethod.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_def flags an instance bang method that does not begin with a verb" do
    expected = [ "Begin the bang method `strict_loading!` with a verb that describes the operation (for example `disable_strict_loading!`)." ]

    assert_equal expected, offenses_for("def strict_loading!(value)\n  value\nend").map(&:message)
  end

  test "#on_defs flags a class bang method that does not begin with a verb" do
    assert_equal 1, offenses_for("def self.invalid!\n  nil\nend").size
  end

  test "#on_def flags a bang method whose verb is only a prefix of its first word" do
    assert_equal 1, offenses_for("def settlement!\n  nil\nend").size
  end

  test "#on_def allows a bang method that is a verb or begins with a verb" do
    sources = [
      "def unblock!\n  nil\nend",
      "def disable_strict_loading!\n  nil\nend",
      "def self.set_strict_loading!(value)\n  value\nend",
      "def soft_delete!\n  nil\nend"
    ]

    assert_equal([ 0, 0, 0, 0 ], sources.map { |source| offenses_for(source).size })
  end

  test "#on_def allows a method without a bang and a call to a bang method" do
    assert_equal([ 0, 0 ], [ "def strict_loading\n  nil\nend", "record.strict_loading!(false)" ].map { |source| offenses_for(source).size })
  end

  test "#on_def accepts a house verb from the allowed verbs option" do
    assert_empty offenses_for("def reticulate_splines!\n  nil\nend", "AllowedVerbs" => [ "reticulate" ])
  end
end
