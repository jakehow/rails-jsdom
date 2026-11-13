require "test_helper"
require "generators/rails_jsdom/install/install_generator"

module RailsJsdom
  class InstallGeneratorTest < Rails::Generators::TestCase
    tests RailsJsdom::Generators::InstallGenerator
    destination File.expand_path("../../tmp/install_generator", __dir__)

    setup do
      prepare_destination
      write "test/test_helper.rb", %(ENV["RAILS_ENV"] ||= "test"\nrequire_relative "../config/environment"\nrequire "rails/test_help"\n)
      write ".gitignore", "/log/*\n"
      Generators::InstallGenerator.any_instance.stubs(:run).with("npm --version", capture: true, verbose: false).returns("11.10.0\n")
    end

    test "requires the library after rails/test_help" do
      run_generator %w[--skip-npm]

      assert_file "test/test_helper.rb", %r{require "rails/test_help"\nrequire "rails_jsdom"\n}
    end

    test "requires the library once when run again" do
      run_generator %w[--skip-npm]
      run_generator %w[--skip-npm]

      assert_file "test/test_helper.rb" do |helper|
        assert_equal 1, helper.scan("require \"rails_jsdom\"").size
      end
    end

    test "creates the interactions directory" do
      run_generator %w[--skip-npm]

      assert_file "test/interactions/.keep"
    end

    test "creates package.json with jsdom and esbuild when the app has none" do
      run_generator %w[--skip-npm]

      assert_file "package.json" do |package|
        assert_equal({ "private" => true, "devDependencies" => { "jsdom" => "^31.0.0", "esbuild" => "^0.28.2" } }, JSON.parse(package))
      end
    end

    test "adds the packages to an existing package.json and keeps the versions it lists" do
      write "package.json", JSON.generate("name" => "shop", "devDependencies" => { "jsdom" => "^28.0.0", "prettier" => "^3.0.0" })
      run_generator %w[--skip-npm]

      assert_file "package.json" do |package|
        assert_equal({ "name" => "shop", "devDependencies" => { "jsdom" => "^28.0.0", "esbuild" => "^0.28.2", "prettier" => "^3.0.0" } }, JSON.parse(package))
      end
    end

    test "runs npm install" do
      Generators::InstallGenerator.any_instance.expects(:run).with("npm install").once

      run_generator
    end

    test "skips npm install with --skip-npm" do
      Generators::InstallGenerator.any_instance.expects(:run).with("npm install").never

      run_generator %w[--skip-npm]
    end

    test "makes npm wait 7 days before installing a new release" do
      run_generator %w[--skip-npm]

      assert_file ".npmrc", "min-release-age=7\n"
    end

    test "adds the release age to an existing .npmrc and keeps its settings" do
      write ".npmrc", "fund=false"
      run_generator %w[--skip-npm]

      assert_file ".npmrc", "fund=false\nmin-release-age=7\n"
    end

    test "keeps a release age the app already set" do
      write ".npmrc", "min-release-age=14\n"
      run_generator %w[--skip-npm]

      assert_file ".npmrc", "min-release-age=14\n"
    end

    test "warns when npm is too old to hold back new releases" do
      Generators::InstallGenerator.any_instance.stubs(:run).with("npm --version", capture: true, verbose: false).returns("10.9.2\n")

      assert_match(/npm 10.9.2 ignores min-release-age/, run_generator(%w[--skip-npm]))
    end

    test "reads the npm version when npm warns about the release age setting" do
      Generators::InstallGenerator.any_instance.stubs(:run).with("npm --version", capture: true, verbose: false).returns("npm warn Unknown project config \"min-release-age\". This will stop working in the next major version of npm.\n11.9.0\n")

      assert_match(/npm 11.9.0 ignores min-release-age/, run_generator(%w[--skip-npm]))
    end

    test "says nothing about Action Cable's adapter, because each test installs its own" do
      assert_no_match(/cable|adapter/i, run_generator(%w[--skip-npm]))
    end

    test "says nothing about npm when it holds back new releases" do
      assert_no_match(/ignores min-release-age/, run_generator(%w[--skip-npm]))
    end

    test "ignores node_modules in .gitignore" do
      run_generator %w[--skip-npm]

      assert_file ".gitignore", "/log/*\n\n/node_modules\n"
    end

    test "leaves a .gitignore that already ignores node_modules unchanged" do
      write ".gitignore", "node_modules/\n"
      run_generator %w[--skip-npm]

      assert_file ".gitignore", "node_modules/\n"
    end

    test "leaves an app without a .gitignore without one" do
      File.delete(File.join(destination_root, ".gitignore"))
      run_generator %w[--skip-npm]

      assert_no_file ".gitignore"
    end

    private

    def write(relative, content)
      file = File.join(destination_root, relative)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
    end
  end
end
