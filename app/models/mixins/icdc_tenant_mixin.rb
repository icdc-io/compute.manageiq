module IcdcTenantMixin
  extend ActiveSupport::Concern
  ALLOWED_CUSTOM_ATTRIBUTES = %w(exp_date admin_email classifiers)

  included do
    virtual_attribute :project_users, :string
    virtual_attribute :available_users, :string
    virtual_attribute :available_roles, :string
    virtual_attribute :project_details, :string
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

    api_relay_method :exclude_users do |options|
      options
    end

    def project_users
      project_users = []
      uniq_users = self.users
      uniq_users.each do |user|
        project_users.push({:email => user.email, :name => user.name, :roles => (user.miq_groups & self.miq_groups).collect{|x| [:id => x.description.split(".").last, :name => x.description.split(".").last.capitalize]}.flatten})
      end
      project_users
    end

    def available_users
      [User.in_my_region.collect{|x| [ :id => x.id, :email => x.email, :name => x.name]}.uniq].flatten
    end

    def available_roles
      [{ :id => "admin", :name => "Admin"}, {:id => "billing",:name  => "Billing"}, {:id => "member", :name => "Member"}]
    end

    def project_details
      raise "Unable to show details, #{self.name} isn't a project" unless self.project?
      {
        :available_roles => self.available_roles,
        :project_users   => self.project_users,
        :available_users => self.available_users,
        :details         => project_info(self)
      }
    end

    def project_info(project)
      info = {}
      project.regional_tenants.first.custom_attributes.each do |ca|
        info[ca.name] = ca.value
      end
      info
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
    project.id
  end

  def set_user_role(user, role)
    user.miq_groups.push(self.miq_groups.select{|x| x.description.include?(role)}.first) unless user.miq_groups.include?(self.miq_groups.select{|x| x.description.include?(role)}.first)
    user.id
  end

  def edit_project(data)
    raise "Unable to edit: not tenant" if self.tenant?
    self.update_attributes(:name => data["name"], :description => data["description"])
    begin
      ALLOWED_CUSTOM_ATTRIBUTES.each{|attr| self.miq_custom_set(attr, data[attr])}
    rescue => e
      _log.error("unable to set custom attributes #{e}")
    end
    self.id
  end

  def delete_project
    raise "Unable to delete: not tenant" if self.tenant?
    self.miq_groups.each{|group| group.destroy if group.group_type != 'tenant'}
    self.destroy
    self.id
  end

  def invite_users(data)
    users_emails = data["emails"]
    invited_ids = []
    role = data["role"]
    users_emails.each do |ue|
      user = User.find_by(:email => ue)
      raise ArgumentError, "Unable to invite #{ue} as #{role}. Check user email" unless user
      self.set_user_role(user, role)
      invited_ids.push(user.id)
    end
    invited_ids
  end

  def exclude_users(data)
    users_emails = data["emails"]
    excluded_ids = []
    users_emails.each do |ue|
      user = User.find_by(:email => ue)
      raise ArgumentError, "Something went wrong" unless user
      user.miq_groups = user.miq_groups.reject{|x| x.tenant == self}
      user.save!
      excluded_ids.push(user.id)
    end
    excluded_ids
  end
end
