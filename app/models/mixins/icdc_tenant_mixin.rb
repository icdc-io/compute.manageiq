module IcdcTenantMixin
  extend ActiveSupport::Concern
  ALLOWED_CUSTOM_ATTRIBUTES = %w(exp_date)

  included do
    virtual_has_one   :account
    virtual_attribute :account_users, :string
    virtual_attribute :get_account_users, :string # Legacy, used in change-ownership
    virtual_attribute :project_users, :string
    virtual_attribute :available_users, :string
    virtual_attribute :available_roles, :string
    virtual_attribute :project_details, :string
    virtual_attribute :admins, :string
    virtual_attribute :available_networks, :string
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

    api_relay_method :services_change_tenant do |options|
      options
    end
  
    def account
      project? && parent || self
    end
 
    def account_users
      users.map do |account_user|
        user = account_user.as_json
        user["group"] = self.miq_groups.select{|x| x.description.include?(".member")}.first.description
        user
      end
    end
    alias_method :get_account_users, :account_users

    def available_networks

      # OVN Networks
      nets = CloudSubnet.all.select{ |subnet|
        subnet.name.match?("#{MiqRegion.my_region.description.downcase}_#{account.name.downcase}_")
      }.map{ |subnet|
	{
	  :subnet => subnet.name, :description => (subnet.name.split("_")[2..-1]&.join("_") || subnet.name).humanize(), 
	  :ip_range =>  subnet.extra_attributes[:allocation_pools][0] 
	}
      }
      # Foreman Networks
      foreman_tenant = Icdc::Foreman::Organization.new(:region => MiqRegion.my_region.region, :tenant_name => account.name)
      nets += foreman_tenant.subnets.map{ |subnet| {:subnet => subnet.name, :description => subnet.description} } if foreman_tenant.ready?
      nets
      
    end

    def project_users
      users.map do |user|
        {
         :email => user.email,
         :name => user.name,
         :roles => (user.miq_groups & self.miq_groups).collect{|x| [:id => x.description.split(".").last,
         :name => x.description.split(".").last.capitalize]}.flatten
        }
      end
    end

    def available_users
      [(User.in_my_region - User.find_tagged_with(:any => 'true', :ns => '/managed/system_user')).collect{|x| [ :id => x.id, :email => x.email, :name => x.name, :group => x.current_group]}.uniq].flatten
    end

    def available_roles
      [
        { :id => "admin", :name => "Admin" },
        { :id => "billing",:name => "Billing" },
        { :id => "member", :name => "Member" }
      ]
    end

    def project_details
      raise "Unable to show details, #{self.name} isn't a project" unless self.project?
      {
        :project_users   => self.project_users,
        :available_users => self.available_users,
        :admins          => self.admins,
        :details         => self.project_info
      }
    end

    def project_info
      info = {}
      self.regional_tenants.first.custom_attributes.each do |ca|
        info[ca.name] = ca.value
      end
      info
    end

    def admins
      miq_groups.select{|x| x.description.include?(".admin")}.first.users.collect(&:email)
    end
  end

  def create_project(data)
    project = Tenant.create!(:name => data["name"], :description => data["description"], :parent => self, :divisible => false)
    non_included = []
    data["admins"].each do |admin|
      user = User.in_my_region.find_by(:email => admin)
      user ? project.set_user_role(user, 'admin') : non_included.push(user)
    end
    begin
      ALLOWED_CUSTOM_ATTRIBUTES.each{|attr| project.miq_custom_set(attr, data[attr])}
    rescue => e
      _log.error("Unable to set custom attributes for tenant #{self}: #{e}")
    end
    non_included
  end

  def set_user_role(user, role)
    user.miq_groups.push(self.miq_groups.select{|x| x.description.include?(role)}.first) unless user.miq_groups.include?(self.miq_groups.select{|x| x.description.include?(role)}.first)
    user.id
  end

  def edit_project(data)
    raise "Unable to edit: not tenant" if self.tenant?
    self.update_attributes(:name => data["name"], :description => data["description"])
    change_groups_name(data["name"]) if data["name"]
    non_included = []
    unless data["admins"].nil?
      data["admins"].each do |admin|
        user = User.in_my_region.find_by(:email => admin)
        user ? self.set_user_role(user, 'admin') : non_included.push(user)
      end
    end
    begin
      ALLOWED_CUSTOM_ATTRIBUTES.each{|attr| self.miq_custom_set(attr, data[attr])}
    rescue => e
      _log.error("unable to set custom attributes #{e}")
    end
    non_included
  end

  def delete_project
    raise "Unable to delete: not tenant" if self.tenant?
    begin
      self.miq_groups.each{|group| group.destroy if group.group_type != 'tenant'}
      self.destroy
    rescue => error
      _log.error("Unable to delete '#{self.name}' project => #{error.message}")
    end
    self.id
  end

  def invite_users(data)
    users_emails = data["emails"]
    users_names = data["users_names"]
    invited_ids = []
    role = data["role"]
    users_emails.each do |ue|
      user = User.in_my_region.find_by(:email => ue)
      user ||= User.create(:name => users_names["#{ue}"] , :userid => ue , :email => ue)
      self.set_user_role(user, role)
      invited_ids.push(user.id)
      user.miq_groups = user.miq_groups.reject{|x| x.description.include?("Demo_Account")}
      user.save!
    end
    invited_ids
  end

  def exclude_users(data)
    users_emails = data["emails"]
    excluded_ids = []
    users_emails.each do |ue|
      user = User.in_my_region.find_by(:email => ue)
      raise ArgumentError, "Something went wrong" unless user
      user.miq_groups = user.miq_groups.reject{|x| x.tenant == self}
      services = Service.where(:evm_owner => user).select{|x| x.tenant == self}
      transfer_services_to_admin(services, User.find_by(:email => self.admins.first)) unless services.empty?
      user.save!
      excluded_ids.push(user.id)
      user.destroy! if user.miq_groups.empty?
    end
    excluded_ids
  end

  def services_change_tenant(data)
    group = Tenant.find(data["tenant"]).miq_groups.select{|mg| mg.description.include?("member")}.first
    data["services"].each do |service_id|
      next unless MiqRegion.id_in_current_region?(service_id)
      service = Service.find(service_id)
      next unless service
      if service && check_permissions(service)
        service.update!(:miq_group => group)
        service.update!(:tenant => group.tenant)
        service.vms.each do |vm|
          vm.update!(:miq_group => group)
          vm.update!(:tenant => group.tenant)
        end
      end
    end
    self.id
  end

  def check_permissions(service)
    [service.tenant.ancestor_ids, service.tenant.id].flatten.include?(User.current_user.current_tenant.id)
  end

  def change_groups_name(new_name)
    _log.info("new name #{new_name}")
    _log.info("miq_groups #{miq_groups.inspect}")
    miq_groups.each{|group| group.update!(:description => [new_name, group.description.split(".").last].join(".")) if group.group_type != 'tenant'}
  end

  def transfer_services_to_admin(services, admin)
    services.each do |service|
      service.evm_owner = admin
      service.vms.each do |vm|
        vm.evm_owner = admin
        vm.save!
      end
      service.save!
    end
  end

  def build_account_infrastructure
    return if project?
    Icdc::Account::Infrastructure.build(name)
  end

end
