require_relative "lib/rails_jsdom/version"

Gem::Specification.new do |spec|
  spec.name = "rails-jsdom"
  spec.version = RailsJsdom::VERSION
  spec.authors = [ "Jake Howerton" ]
  spec.email = [ "jake.howerton@gmail.com" ]
  spec.summary = "Browserless Stimulus and Turbo interaction tests for Rails, on jsdom."
  spec.description = "rails-jsdom runs your real Rails pages, Stimulus controllers and Turbo in a persistent Node + jsdom process, routing page fetches back into Rails in-process. Interaction tests read like system tests without Capybara, a server or a browser."
  spec.homepage = "https://github.com/jakehow/rails-jsdom"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "https://jakehow.github.io/rails-jsdom/",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.{rb,js}", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = [ "lib" ]
  spec.post_install_message = "rails-jsdom: set up interaction tests in your app with `bin/rails generate rails_jsdom:install`."
  spec.extra_rdoc_files = [ "README.md", "CHANGELOG.md", "LICENSE" ]
  spec.rdoc_options = [ "--main", "README.md", "--markup", "markdown", "--title", "rails-jsdom" ]

  spec.add_dependency "actioncable", ">= 8.1"
  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "importmap-rails", ">= 2.0"
  spec.add_dependency "nokogiri", ">= 1.15"
  spec.add_dependency "propshaft", ">= 1.0"
  spec.add_dependency "turbo-rails", ">= 2.0"
end
