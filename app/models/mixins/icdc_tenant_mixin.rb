module IcdcTenantMixin
  extend ActiveSupport::Concern
  ALLOWED_CUSTOM_ATTRIBUTES = %w(exp_date admin_email classifiers)

  included do
    extend InterRegionApiMethodRelay
    api_relay_method :create_project do |options|
      options
    end

    api_relay_method :edit_project do |options|
      options
    end

    api_relay_method :delete_project do |options|
      options
    end

    api_relay_method :invite_users do |options|
      options
    end

    api_relay_method :exclude_user do |options|
      options
    end
  end

  def create_project(data)
    user = User.find_by(:email => data["admin_email"])
    raise ArgumentError, "Unable to set user #{data["admin_email"]} as admin. Check user email" unless user
    project = Tenant.create!(:name => data["name"], :description => data["description"], :parent => self, :divisible => false)
    project.set_user_role(user, 'admin')
    begin
      ALLOWED_CUSTOM_ATTRIBUTES.each{|attr| project.miq_custom_set(attr, data[attr])}
    rescue => e
      _log.error("Unable to set custom attributes for tenant #{self}: #{e}")
    end
    project
  end

  def set_user_role(user, role)
    user.miq_groups.push(self.miq_groups.select{|x| x.description.include?(role)}.first)
    user.save!
  end

  def edit_project(data)
    self.update_attributes(:name => data["name"], :description => data["description"])
    begin
      ALLOWED_CUSTOM_ATTRIBUTES.each{|attr| self.miq_custom_set(attr, data[attr])}
    rescue => e
      _log.error("unable to set custom attributes #{e}")
    end
    self
  end

  def delete_project
    raise "Unable to delete: not tenant" if self.tenant?
    self.miq_groups.each{|group| group.destroy if group.group_type != 'tenant'}
    self.destroy
  end

  def invite_users(data)
    users_emails = data["users_emails"].split(",")
    role = data["role"]
    users_emails.each do |ue|
      user = User.find_by(:email => ue)
      raise ArgumentError, "Unable to invite #{ue} as #{role}. Check user email" unless user
      self.set_user_role(user, role)
    end
  end

  def exclude_user(data)
    user = User.find_by(:email => data["email"])
    raise ArgumentError, "Something went wrong" unless user
    user.miq_groups = user.miq_groups.reject{|x| x.tenant == self}
    user.save!
  end
end
