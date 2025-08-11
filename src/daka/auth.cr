require "kemal-basic-auth"

class CustomAuthHandler < Kemal::BasicAuth::Handler
  only ["/admin"]

  def call(context)
    return call_next(context) unless only_match?(context)
    super
  end
end

Kemal.config.auth_handler = CustomAuthHandler

basic_auth "user", ENV.fetch("DAKAPWD", "1234567")
