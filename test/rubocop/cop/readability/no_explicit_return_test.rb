# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_explicit_return"

class RuboCop::Cop::Readability::NoExplicitReturnTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoExplicitReturn" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoExplicitReturn.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_return flags a guard clause return" do
    assert_equal 1, offenses_for("def go(x)\n  return unless x\n  x\nend").size
  end

  test "#on_return flags a return with a value" do
    assert_equal 1, offenses_for("def go\n  return 1\nend").size
  end

  test "#on_return accepts an implicit return" do
    assert_empty offenses_for("def go(x)\n  x ? 1 : 2\nend")
  end
end
