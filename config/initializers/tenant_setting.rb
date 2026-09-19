Rails.application.config.to_prepare do
  TenantSetting.install!
end
