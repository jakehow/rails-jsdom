# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_explicit_nil_return"

class RuboCop::Cop::Readability::NoExplicitNilReturnTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoExplicitNilReturn" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoExplicitNilReturn.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_return flags a bare return of nil" do
    assert_equal [ RuboCop::Cop::Readability::NoExplicitNilReturn::MSG_BARE ], offenses_for("def a\n  return nil\nend").map(&:message)
  end

  test "#on_return names the modifier of a return of nil behind an if" do
    assert_includes offenses_for("def a(b)\n  return nil if b\n  1\nend").first.message, "return nil if"
  end

  test "#on_return names the modifier of a return of nil behind an unless" do
    assert_includes offenses_for("def a(b)\n  return nil unless b\n  1\nend").first.message, "return nil unless"
  end

  test "#on_return flags a bare return of nil inside a block if" do
    assert_equal [ RuboCop::Cop::Readability::NoExplicitNilReturn::MSG_BARE ], offenses_for("def a(b)\n  if b\n    return nil\n  end\n  1\nend").map(&:message)
  end

  test "#on_return flags a bare return of nil at the top of a file" do
    assert_equal [ RuboCop::Cop::Readability::NoExplicitNilReturn::MSG_BARE ], offenses_for("return nil").map(&:message)
  end

  test "#on_return accepts a return of a value" do
    assert_empty offenses_for("def a\n  return 1\nend")
  end

  test "#on_return accepts a bare return" do
    assert_empty offenses_for("def a\n  return\nend")
  end
end
