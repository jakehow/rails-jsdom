# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_unnecessary_boolean"

class RuboCop::Cop::Readability::NoUnnecessaryBooleanTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoUnnecessaryBoolean" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoUnnecessaryBoolean.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_if flags an if whose branches are only boolean literals" do
    assert_equal 1, offenses_for("if a?\n  true\nelse\n  false\nend").size
  end

  test "#on_if flags an unless whose branches are only boolean literals" do
    assert_equal 1, offenses_for("unless a?\n  false\nelse\n  true\nend").size
  end

  test "#on_if flags an elsif chain whose branches are only boolean literals" do
    assert_equal 1, offenses_for("if a?\n  true\nelsif b?\n  false\nelse\n  true\nend").size
  end

  test "#on_case flags a case whose branches are only boolean literals" do
    assert_equal 1, offenses_for("case kind\nwhen :a then true\nelse false\nend").size
  end

  test "#on_def flags a boolean flag set more than once in a method" do
    source = "def ready?(items)\n  found = false\n  items.each { |item| found = true if item.ready? }\n  found\nend"

    assert_equal [ "Boolean flag `found` is set more than once: compose a predicate instead." ], offenses_for(source).map(&:message)
  end

  test "#on_def flags a constant boolean after an action in an instance method" do
    assert_equal 1, offenses_for("def mark(item)\n  item.update!(done: true)\n  true\nend").size
  end

  test "#on_def flags a constant boolean after an action in a class method" do
    assert_equal 1, offenses_for("def self.reject(item)\n  item.errors.add(:base, :invalid)\n  false\nend").size
  end

  test "#on_block flags a constant boolean after an action in a block" do
    assert_equal 1, offenses_for("task.with_lock do\n  task.unblock!\n  true\nend").size
  end

  test "#on_def allows a boolean result inside a branch that does work" do
    assert_empty offenses_for("task.with_lock do\n  if task.blocked?\n    task.unblock!\n    true\n  else\n    false\n  end\nend")
  end

  test "#on_if allows the condition itself a lone literal body and an if without else" do
    sources = [ "def ready?\n  task.blocked?\nend", "def enabled?\n  true\nend", "if a?\n  true\nend" ]

    assert_equal([ 0, 0, 0 ], sources.map { |source| offenses_for(source).size })
  end

  test "#on_if allows a branch that is not a boolean literal and a ternary" do
    sources = [ "if a?\n  true\nelse\n  b\nend", "case kind\nwhen :a then true\nend", "a? ? true : false" ]

    assert_equal([ 0, 0, 0 ], sources.map { |source| offenses_for(source).size })
  end

  test "#on_def allows a boolean variable assigned once" do
    assert_empty offenses_for("def run\n  ok = false\n  ok\nend")
  end

  test "#on_if accepts an if with an empty else branch" do
    assert_empty offenses_for("if a?\n  true\nelse\nend")
  end

  test "#on_def accepts a method with an empty body" do
    assert_empty offenses_for("def run\nend")
  end
end
