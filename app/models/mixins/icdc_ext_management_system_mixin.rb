module IcdcExtManagementSystemMixin
  extend ActiveSupport::Concern

  included do
    virtual_column :default_security_group, :type => :json
  end

  def default_security_group
    security_groups.find_by(name: "Default") if self.class.name == "ManageIQ::Providers::Redhat::NetworkManager"
  end
end

