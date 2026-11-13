# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_nil_ternary_branch"

class RuboCop::Cop::Readability::NoNilTernaryBranchTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoNilTernaryBranch" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoNilTernaryBranch.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_if flags nil on the else branch" do
    assert_equal 1, offenses_for("a ? b : nil").size
  end

  test "#on_if flags nil on the then branch" do
    assert_equal 1, offenses_for("a ? nil : b").size
  end

  test "#on_if allows a ternary without nil and a plain if" do
    assert_equal([ 0, 0 ], [ "a ? b : c", "if a\n  nil\nelse\n  b\nend" ].map { |source| offenses_for(source).size })
  end
end
