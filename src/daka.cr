require "./daka/**"
require "kemal"

get "/daka" do
  "hello world!"
end

Kemal.run
