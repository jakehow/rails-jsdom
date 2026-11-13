# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_nil_condition_check"

class RuboCop::Cop::Readability::NoNilConditionCheckTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoNilConditionCheck" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoNilConditionCheck.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_if flags nil? as an if condition" do
    assert_equal 1, offenses_for("go if value.nil?").size
  end

  test "#on_if flags nil? as an unless condition" do
    assert_equal 1, offenses_for("go unless value.nil?").size
  end

  test "#on_if flags nil? as a ternary condition" do
    assert_equal 1, offenses_for("value.nil? ? 1 : 2").size
  end

  test "#on_if allows truthiness, nil? with arguments and blank?" do
    sources = [ "go if value", "go if value.nil?(1)", "go if value.blank?" ]

    assert_equal([ 0, 0, 0 ], sources.map { |source| offenses_for(source).size })
  end
end
