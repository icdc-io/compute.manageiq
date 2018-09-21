module TenantQuotableMixin
  extend ActiveSupport::Concern
  include QuotableMixin

  included do
    has_many :tenant_quotas

    has_many :quota_holder_subtenants, class_name: "Tenant", foreign_key: "quota_holder_id"
    has_many :quota_holder_users, class_name: "User", foreign_key: "quota_holder_id"

    belongs_to :quota_holder, :class_name => 'Tenant'
  end


  def get_quotas
    tenant_quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  def set_quotas(quotas)
    updated_keys = []

    self.class.transaction do
      quotas.each do |name, values|
        next if values[:value].nil?

        name = name.to_s
        q = tenant_quotas.detect { |tq| tq.name == name } || tenant_quotas.build(:name => name)
        q.update_attributes!(values)
        updated_keys << name
      end
      # Delete any quotas that were not passed in
      tenant_quotas.destroy_missing(updated_keys)
      # unfortunatly, an extra scope is created in destroy_missing, so we need to reload the records
      clear_association_cache
    end

    get_quotas
  end

  def used_quotas
    tenant_quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash.merge(:value => q.used)
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  # Amount of quotas allocated to the immediate child tenants
  def allocated_quotas
    tenant_quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash.merge(:value => q.allocated)
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  # Amount of quotas available to be allocated to child tenants
  def available_quotas
    used_bunch = used_quotas_bunch_new
    allocated_bunch = allocated_quotas_bunch
    tenant_quotas.each_with_object({}) do |q, h|
      used = used_bunch[q.name.to_sym]
      allocated = allocated_bunch[q.name.to_sym]
      h[q.name.to_sym] = q.quota_hash.merge(:value => q.value - used - allocated)
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  def combined_quotas
    unless tenant_quotas.empty?
      used_bunch = used_quotas_bunch
      allocated_bunch = allocated_quotas_bunch
    end

    tenant_quotas.each_with_object({}) do |q, h|
      used = used_bunch[q.name.to_sym]
      allocated = allocated_bunch[q.name.to_sym]
      h[q.name.to_sym] = q.quota_hash
      h[q.name.to_sym][:name] = q.name.split("_").first
      h[q.name.to_sym][:allocated]   = allocated
      h[q.name.to_sym][:used]        = used
      h[q.name.to_sym][:available]   = q.value - used - allocated
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  def build_quota_tree
    root_tenant_node = {
        type:                 "tenant",
        name:                 name,
        title:                description,
        edit_action:          "order",
        service_template_id:  Quota.service_template.id,
        children:             tenant_children,
        locations:            []
    }
    manage_locations(root_tenant_node)

    root_tenant_node
  end

  def tenant_children
    subtenants_children.concat(users_children)
  end

  def subtenants_children
    self.children.map do |subtenant|
      subtenant_node = {
          name:         subtenant.name,
          title:        subtenant.description,
          type:         "tenant",
          children:     subtenant.tenant_children,
          locations:    [],
          edit_action:  "edit",
          manager:      subtenant.managers[0]&.attributes&.slice("name", "email")
      }

      manage_locations(subtenant_node, subtenant.id)
      subtenant_node
    end
  end

  def users_children
    self.users.map do |user|
      {
        id:           user.id,
        name:         user.name,
        email:        user.email,
        title:        user.userid,
        type:         "user",
        locations:    user.user_resources_by_locations,
        edit_action: "edit"
      }
    end
  end

  def quota
    combined_quotas
  end
 
  def monthly_chargeback(months)
    chargeback_for = [DateTime.now.month]
    full_months = [DateTime.now.at_beginning_of_month]
    if months > 1
      for number_of_month in 1..months - 1
        chargeback_for.push(number_of_month.month.ago.month)
        full_months.push(number_of_month.month.ago.at_beginning_of_month)
      end
    end
    services = find_services_by_owner
    if services.empty?
      return full_months.map { |month| {"start_date": month, "cost": 0} }
    end
    costs = services.flat_map { |service| service.total_costs_monthly(chargeback_for) }
    if costs.empty?
      return full_months.map { |month| {"start_date": month, "cost": 0} }
    end
    group_bydate_and_sum(costs).sort_by { |chb| chb[:start_date] }.reverse 
  end
 
  def current_chargeback
    services = find_services_by_owner
    costs = services.flat_map { |service| service.total_costs_bydate('current') }
    group_bydate_and_sum(costs).first || {"start_date": Date.today.at_beginning_of_month, "cost": 0}
  end

  def last_chargeback
    services = find_services_by_owner
    costs = services.flat_map { |service| service.total_costs_bydate('last') }
    group_bydate_and_sum(costs).first || {"start_date": Date.today.at_beginning_of_month - 1.month  , "cost": 0}
  end

  def find_services_by_owner
    Service.where(tenant_id: subtree_ids)
  end

  def services_chargebacks
    services = find_services_by_owner
    costs = services.flat_map { |service| service.total_costs_bydate }
    group_bydate_and_sum(costs)
  end

  def update_quota_holder_associations
    quota_holder = tenant_quotas.present? ? self : nil
    update_quota_holder_recursively(quota_holder)
  end

  def update_quota_holder_recursively(quota_holder)
    update_attribute(:quota_holder, quota_holder)

    children.each do |subtenant|
      if subtenant.tenant_quotas.empty?
        subtenant.update_attribute(:quota_holder, quota_holder)
        subtenant.update_quota_holder_recursively(quota_holder)
      else
        subtenant.update_quota_holder_recursively(subtenant)
      end
    end


    users.each do |user|
      user.update_attribute(:quota_holder, quota_holder)
    end
  end

  # private

  def allocated_quotas_bunch
    allocated_q = Hash.new(0)

    children.includes(:tenant_quotas).each do |subtenant|
      subtenant.tenant_quotas.each do |quota|
        allocated_q[quota.name.to_sym] += quota.value unless quota.value.nil?
      end
    end
    allocated_q
  end

  def quotable_resources
    @quotable_resources ||= tenant_quotas.map{ |quota| quota.name.split("_").first }
  end

  def used_quotas_bunch
    used_q = Hash.new(0)
    quotable_resources.each do |resource_name|
      used_q["#{resource_name}_allocated".to_sym] += resource_used(resource_name)
    end
    traverse_descendants(self, used_q)
    used_q
  end

  def used_quotas_bunch_new
    used_q = Hash.new(0)
    tenant_ids = Tenant.where(quota_holder: id).pluck(:id)
    vms = Vm.where('tenant_id' => tenant_ids).includes(:hardware => :disks).select(&:active?)
    for vm in vms
      used_q["cpu_allocated".to_sym] += vm.cpu_total_cores 
      used_q["mem_allocated".to_sym] += vm.ram_size_in_bytes / 1.gigabyte
      used_q["storage_allocated".to_sym] += vm.allocated_disk_storage / 1.gigabyte
    end
    used_q
  end

  def traverse_descendants(tenant, used_q)
    tenant.children.each do |subtenant|
      if subtenant.tenant_quotas.empty?

        quotable_resources.each do |resource_name|
          used_q["#{resource_name}_allocated".to_sym] += subtenant.resource_used(resource_name)
        end

        traverse_descendants(subtenant, used_q)
      end
    end
  end

end
