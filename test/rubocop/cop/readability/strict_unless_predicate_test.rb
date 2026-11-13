# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/strict_unless_predicate"

class RuboCop::Cop::Readability::StrictUnlessPredicateTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/StrictUnlessPredicate" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::StrictUnlessPredicate.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_if flags a block unless" do
    assert_equal 1, offenses_for("unless ready?\n  go\nend").size
  end

  test "#on_if flags a modifier unless without a predicate" do
    assert_equal 1, offenses_for("go unless ready").size
  end

  test "#on_if flags a modifier unless with a compound condition" do
    assert_equal 1, offenses_for("go unless a && b?").size
  end

  test "#on_if flags a modifier unless that spans lines" do
    assert_equal 1, offenses_for("go(\n  1\n) unless ready?").size
  end

  test "#on_if allows a single line modifier unless with a predicate and an if" do
    assert_equal([ 0, 0 ], [ "go unless ready?", "go if ready" ].map { |source| offenses_for(source).size })
  end
end
