# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_boolean_ternary_branch"

class RuboCop::Cop::Readability::NoBooleanTernaryBranchTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoBooleanTernaryBranch" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoBooleanTernaryBranch.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_if flags false on the else branch" do
    assert_equal 1, offenses_for("a ? b : false").size
  end

  test "#on_if flags true on the then branch" do
    assert_equal 1, offenses_for("a ? true : b").size
  end

  test "#on_if allows a ternary without boolean literals and a plain if" do
    assert_equal([ 0, 0 ], [ "a ? b : c", "if a\n  true\nelse\n  b\nend" ].map { |source| offenses_for(source).size })
  end
end
