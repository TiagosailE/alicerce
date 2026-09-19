Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :none
    policy.script_src :self
    policy.style_src :self
    policy.img_src :self, :data
    policy.font_src :self
    policy.connect_src :self
    policy.manifest_src :self
    policy.base_uri :none
    policy.form_action :self
    policy.frame_ancestors :none
    policy.object_src :none
  end
end
