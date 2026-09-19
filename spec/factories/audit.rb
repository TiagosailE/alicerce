FactoryBot.define do
  factory :audit_event, class: "Audit::Event" do
    organization
    actor factory: :user
    action { "signed_in" }
    subject_type { "Identity::User" }
    sequence(:subject_id)
    field_changes { {} }
  end
end
