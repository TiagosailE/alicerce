module Identity
  class OrganizationSerializer
    def initialize(organization)
      @organization = organization
    end

    def as_json
      { id: @organization.id, name: @organization.name, time_zone: @organization.time_zone, demo: @organization.demo? }
    end
  end
end
