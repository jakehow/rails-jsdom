# frozen_string_literal: true

require "minitest/autorun"
require "rubocop"
require "active_support/testing/declarative"
require_relative "../../../../rubocop/cop/readability/no_next_unless"

class RuboCop::Cop::Readability::NoNextUnlessTest < Minitest::Test
  extend ActiveSupport::Testing::Declarative

  def offenses_for(source)
    config = RuboCop::Config.new("Readability/NoNextUnless" => { "Enabled" => true })
    cop = RuboCop::Cop::Readability::NoNextUnless.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, "app/models/example.rb")
    RuboCop::Cop::Commissioner.new([ cop ]).investigate(processed).offenses
  end

  test "#on_if flags a modifier next unless" do
    assert_equal 1, offenses_for("items.each do |item|\n  next unless item.ready?\n  item.run\nend").size
  end

  test "#on_if flags a modifier next with a value unless" do
    assert_equal 1, offenses_for("lock do\n  next false unless ready?\n  run\nend").size
  end

  test "#on_if flags a block unless whose body is next" do
    assert_equal 1, offenses_for("items.each do |item|\n  unless item.ready?\n    next\n  end\n  item.run\nend").size
  end

  test "#on_if allows next if, an explicit if else and an unless without next" do
    sources = [
      "items.each do |item|\n  next if item.done?\n  item.run\nend",
      "lock do\n  if ready?\n    run\n    true\n  else\n    false\n  end\nend",
      "lock { ready? && run }",
      "run unless done?"
    ]

    assert_equal([ 0, 0, 0, 0 ], sources.map { |source| offenses_for(source).size })
  end
end
