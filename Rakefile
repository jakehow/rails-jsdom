require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

task default: :test

require "rdoc/task"

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.title = "rails-jsdom"
  rdoc.main = "README.md"
  rdoc.markup = "markdown"
  rdoc.rdoc_dir = "doc"
  rdoc.rdoc_files.include("README.md", "CHANGELOG.md", "LICENSE", "docs/agents.md", "docs/protocol.md", "docs/reference_apps.md", "lib/**/*.rb")
end

Rake::Task[:rdoc].enhance do
  cp "docs/llms.txt", "doc/llms.txt"
  cp "docs/agents.md", "doc/agents.md"
  cp "docs/protocol.md", "doc/protocol.md"
end

desc "Run the Node tests for the runtime and the ESLint rule, holding their coverage at 100%"
task :test_runner do
  sh "node", "--test", "--experimental-test-coverage",
    "--test-coverage-include=lib/rails_jsdom/runtime.js", "--test-coverage-include=eslint/*.js",
    "--test-coverage-lines=100", "--test-coverage-branches=100", "--test-coverage-functions=100",
    "test/runner/*.test.js", "test/eslint/*.test.js"
end

desc "Lint the JavaScript with ESLint"
task :lint_js do
  sh "node_modules/.bin/eslint", "."
end

Rake::Task[:test].enhance([ :lint_js, :test_runner ])
