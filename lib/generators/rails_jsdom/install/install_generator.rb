require "json"
require "rails/generators"

module RailsJsdom
  # Rails generators for rails-jsdom.
  module Generators
    # Sets an app up for rails-jsdom interaction tests:
    #
    #   bin/rails generate rails_jsdom:install
    #
    # Pass `--skip-npm` to add the Node packages to `package.json` without
    # running `npm install`.
    class InstallGenerator < Rails::Generators::Base
      # The Node packages the app needs. Each range allows newer minor and patch
      # releases but never a new major version.
      PACKAGES = { "jsdom" => "^31.0.0", "esbuild" => "^0.28.2" }.freeze

      # How many days old a package version must be before npm installs it.
      RELEASE_AGE_DAYS = 7

      # The first npm version that understands `min-release-age`.
      RELEASE_AGE_NPM = Gem::Version.new("11.10.0")

      class_option :skip_npm, type: :boolean, default: false, desc: "Add jsdom and esbuild to package.json without running npm install"

      # Requires the library in `test/test_helper.rb`, after `rails/test_help`.
      def require_library
        inject_into_file "test/test_helper.rb", "require \"rails_jsdom\"\n", after: %r{require ["']rails/test_help["']\n}
      end

      # Creates `test/interactions`, where interaction tests live.
      def create_interactions_directory
        create_file "test/interactions/.keep", ""
      end

      # Adds jsdom and esbuild to the development dependencies in
      # `package.json`, creating the file if the app has none. Versions the
      # app already lists are kept.
      def add_node_packages
        package = existing_package || { "private" => true }
        package["devDependencies"] = PACKAGES.merge(package.fetch("devDependencies", {}))
        create_file "package.json", "#{JSON.pretty_generate(package)}\n", force: true
      end

      # Sets `min-release-age` in `.npmrc`, so npm installs only package
      # versions published at least RELEASE_AGE_DAYS days ago. A compromised
      # release of jsdom, esbuild or anything they depend on is usually found
      # and removed within that time. An existing `min-release-age` is kept.
      def delay_new_releases
        settings = npm_settings
        create_file ".npmrc", "#{settings}min-release-age=#{RELEASE_AGE_DAYS}\n", force: true unless settings.match?(/^min-release-age\s*=/)
      end

      # Warns when the app's npm is older than 11.10, which ignores
      # `min-release-age`.
      def check_npm_version
        say_status :warning, "npm #{npm_version} ignores min-release-age, so it would install brand-new releases. Upgrade to npm #{RELEASE_AGE_NPM} or later.", :yellow if npm_version < RELEASE_AGE_NPM
      end

      # Runs `npm install`, unless `--skip-npm` is given.
      def install_node_packages
        run "npm install" unless options.skip_npm?
      end

      # Adds `/node_modules` to `.gitignore`, unless it is already ignored.
      def ignore_node_modules
        gitignore = path(".gitignore")
        append_to_file ".gitignore", "\n/node_modules\n" if File.exist?(gitignore) && !File.read(gitignore).include?("node_modules")
      end

      private

      def npm_settings
        settings = File.exist?(path(".npmrc")) ? File.read(path(".npmrc")) : ""
        settings.empty? || settings.end_with?("\n") ? settings : "#{settings}\n"
      end

      def npm_version
        @npm_version ||= Gem::Version.new(run("npm --version", capture: true, verbose: false).to_s.lines.map(&:strip).grep(/\A\d+(\.\d+)+\z/).last)
      end

      def existing_package
        JSON.parse(File.read(path("package.json"))) if File.exist?(path("package.json"))
      end

      def path(relative)
        File.join(destination_root, relative)
      end
    end
  end
end
