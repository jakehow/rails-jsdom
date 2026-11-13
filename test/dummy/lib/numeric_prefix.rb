class NumericPrefix
  def initialize(app)
    @app = app
  end

  def call(env)
    if (match = env["PATH_INFO"].match(%r{\A/(\d+)(/.*)?\z}))
      env["SCRIPT_NAME"] = "#{env["SCRIPT_NAME"]}/#{match[1]}"
      env["PATH_INFO"] = match[2] || "/"
    end
    @app.call(env)
  end
end
