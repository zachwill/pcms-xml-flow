# Be sure to restart your server when you modify this file.
#
# Internal tool CSP — relaxed for Tailwind CDN + Datastar:
# - `unsafe-eval`: Datastar evaluates expressions via the Function constructor
# - `unsafe-inline`: Tailwind CDN injects styles, Datastar uses inline handlers

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src :self, :https, :data
    policy.img_src :self, :https, :data
    policy.object_src :none

    policy.script_src :self, :https, :unsafe_eval, :unsafe_inline
    policy.style_src :self, :https, :unsafe_inline
  end
end
