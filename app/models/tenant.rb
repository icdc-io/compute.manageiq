require 'ancestry'
require 'ancestry_patch'

class Tenant < ApplicationRecord
  HARDCODED_LOGO = "custom_logo.png"
  HARDCODED_LOGIN_LOGO = "custom_login_logo.png"
  DEFAULT_URL = nil

  include ActiveVmAggregationMixin
  include CustomActionsMixin
  include SvmMetricMixin
  include AccountChargebackMixin
  include QuotableMixin
  include IbaRelationshipMixin 
  include ServiceChargebackMixin
  include ProcessTasksMixin
  include TenantTagsMixin
  include ResourceConsumptionMixin

  acts_as_miq_taggable

  default_value_for :name,        "My Company"
  default_value_for :description, "Tenant for My Company"
  default_value_for :divisible,   true
  default_value_for :use_config_for_attributes, false

  has_ancestry

  has_many :providers
  has_many :ext_management_systems
  has_many :vm_or_templates
  has_many :vms, :inverse_of => :tenant
  has_many :miq_templates, :inverse_of => :tenant
  has_many :service_template_catalogs
  has_many :service_templates

  has_many :tenant_quotas
  has_many :miq_groups
  has_one  :default_users_group, -> { where("description LIKE ?", "g%") }, class_name: 'MiqGroup', dependent: :destroy
  has_many :users, :through => :miq_groups
  has_many :ae_domains, :dependent => :destroy, :class_name => 'MiqAeDomain'
  has_many :miq_requests, :dependent => :destroy
  has_many :miq_request_tasks, :dependent => :destroy
  has_many :services, :dependent => :destroy
  has_many :shares

  virtual_has_one  :quota
  virtual_has_one  :services_in_regions
  virtual_has_one  :account

  belongs_to :default_miq_group, :class_name => "MiqGroup", :dependent => :destroy
  belongs_to :source, :polymorphic => true

  validates :subdomain, :uniqueness => true, :allow_nil => true
  validates :domain,    :uniqueness => true, :allow_nil => true
  validate  :validate_only_one_root
  validates :description, :presence => true
  validates :name, :presence => true, :unless => :use_config_for_attributes?
  validates :name, :uniqueness => {:scope      => :ancestry,
                                   :conditions => -> { in_my_region },
                                   :message    => "should be unique per parent"}
  validate :validate_default_tenant, :on => :update, :if => :default_miq_group_id_changed?

  scope :all_tenants,  -> { where(:divisible => true) }
  scope :all_projects, -> { where(:divisible => false) }

  virtual_column :parent_name,  :type => :string
  virtual_column :display_type, :type => :string
  virtual_column :get_account_users, :type => :string
  virtual_column :get_account, :type => :string
  virtual_column :get_account_subnet, :type => :string
  virtual_column :get_tenant_users, :type => :string

  before_save :nil_blanks
  after_create :create_tenant_group, :create_users_group
  before_destroy :ensure_can_be_destroyed

  def get_account_users
    account_users = []
    account_users = get_account.users if get_account.descendants.empty?
    get_account.descendants.each do |descendant| 
      account_users += descendant.users
    end        
    account_users.map do |account_user|  
      group = MiqGroup.find_by_id(account_user.current_group_id)
      user = account_user.as_json
      user["tags"] = account_user.tags
      user["group"] = group.description
      user
    end  
  end  

  def get_account
    ancestors.each do |ancestor| 
      return ancestor if check_account(ancestor.tags) == 0
    end  
    self
  end
  alias_method :account, :get_account

  def check_account(tags)
    return 0 if tags.find_index { |tag| /\/managed\/account\// =~ tag.name }
  end

  def get_account_subnet    
    network = []
    get_account.tags.each do |tag|
      tag_info = {}
      if /\/managed\/networks\// =~ tag.name
        tag_info["subnet"] = tag.categorization["name"]
        tag_info["description"] = tag.categorization["description"]
        network.push(tag_info)
      end  
    end 
    network    
  end  

  def get_tenant_users
    tenant_users = []
    tenant_users = users
    tenant_users.map do |tenant_user|  
      group = MiqGroup.find_by_id(tenant_user.current_group_id)
      user = tenant_user.as_json
      user["tags"] = tenant_user.tags
      user["group"] = group.get_title
      user
    end  
  end 

  def self.scope_by_tenant?
    true
  end

  def self.with_current_tenant
    current_tenant = User.current_user.current_tenant
    where(:id => current_tenant.id)
  end

  def self.tenant_id_clause(user_or_group)
    strategy = Rbac.accessible_tenant_ids_strategy(self)
    tenant = user_or_group.try(:current_tenant)
    return [] if tenant.root?

    tenant_ids = tenant.accessible_tenant_ids(strategy)

    return if tenant_ids.empty?

    {table_name => {:id => tenant_ids}}
  end

  def all_subtenants
    self.class.descendants_of(self).where(:divisible => true)
  end

  def all_subprojects
    self.class.descendants_of(self).where(:divisible => false)
  end

  def accessible_tenant_ids(strategy = nil)
    (strategy ? send(strategy) : []).append(id)
  end

  def name
    tenant_attribute(:name, :company)
  end

  def parent_name
    parent.try(:name)
  end

  def display_type
    project? ? "Project" : "Tenant"
  end

  def login_text
    tenant_attribute(:login_text, :custom_login_text)
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
    tenant_quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash.merge(:value => q.available)
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  def combined_quotas
    TenantQuota.quota_definitions.each_with_object({}) do |d, h|
      scope_name, _ = d
      q = tenant_quotas.send(scope_name).take || tenant_quotas.build(:name => scope_name, :value => 0)
      h[q.name.to_sym] = q.quota_hash
      h[q.name.to_sym][:allocated]   = q.allocated
      h[q.name.to_sym][:available]   = q.available unless q.new_record?
      h[q.name.to_sym][:used]        = q.used
    end.reverse_merge(TenantQuota.quota_definitions)
  end

  def build_quota_tree
    region, id = Tenant.split_id(self.id)
    if MiqRegion.default? region
      root_tenant_node = {
          "type" => "tenant",
          "name" => self.name,
          "edit_action" => "order",
          "service_template_id" => Quota.service_template.id,
          "children" => tenant_subtenants_nodes,
          "locations" => []
      }
      manage_locations(root_tenant_node)
      set_edit_action_to_children(root_tenant_node)
    end
    root_tenant_node
  end

  def tenant_subtenants_nodes
    children_nodes = []
    for subtenant in self.children
      region, id = Tenant.split_id(subtenant.id)
      subtenant_node = {
          "name" => subtenant.name,
          "type" => "tenant",
          "quota" => subtenant.combined_quotas,
          "children" => subtenant.tenant_subtenants_nodes,
          "locations" => []
      }
      set_edit_action_to_children(subtenant_node)
      manage_locations(subtenant_node, id)
      children_nodes.push(subtenant_node)
    end

    for miq_group in self.miq_groups
      unless miq_group.tenant_group?
        children_nodes.push(miq_group.build_quota_tree)
      end
    end
    children_nodes
  end

  def services_in_regions
    get_services_in_regions do |tenant_in_region|
      tenant_in_region.subtree.inject([]) { |services, desc| services + desc.services }
    end
  end

  def quota
    self.build_quota_tree
  end

  def quota_holder
    return self unless self.tenant_quotas.empty?
    return nil if self.root?
    return self.parent.quota_holder
  end

  # @return [Boolean] Is this a default tenant?
  def default?
    root?
  end

  # @return [Boolean] Is this the root tenant?
  def root?
    !parent_id?
  end

  def tenant?
    divisible?
  end

  def project?
    !divisible?
  end

  def visible_domains
    MiqAeDomain.where(:tenant_id => path_ids).joins(:tenant).order('tenants.ancestry DESC NULLS LAST, priority DESC')
  end

  def enabled_domains
    visible_domains.where(:enabled => true)
  end

  def editable_domains
    ae_domains.where(:source => MiqAeDomain::USER_SOURCE).order('priority DESC')
  end

  def sequenceable_domains
    ae_domains.where.not(:source => MiqAeDomain::SYSTEM_SOURCE).order('priority DESC')
  end

  def any_editable_domains?
    ae_domains.where(:source => MiqAeDomain::USER_SOURCE).count > 0
  end

  def reset_domain_priority_by_ordered_ids(ids)
    uneditable_domains = visible_domains - editable_domains
    uneditable_domains.delete_if { |domain| domain.name == MiqAeDatastore::MANAGEIQ_DOMAIN }
    MiqAeDomain.reset_priority_by_ordered_ids(uneditable_domains.collect(&:id).reverse + ids)
  end

  # The default tenant is the tenant to be used when
  # the url does not map to a known domain or subdomain
  #
  # At this time, urls are not used, so the root tenant is returned
  # @return [Tenant] default tenant
  def self.default_tenant
    root_tenant
  end

  # the root tenant is also referred to as tenant0
  # from this tenant, all tenants are positioned
  #
  # @return [Tenant] the root tenant
  def self.root_tenant
    @root_tenant ||= root_tenant_without_cache
  end

  def self.root_tenant_without_cache
    in_my_region.roots.first
  end

  # NOTE: returns the root tenant
  def self.seed
    root_tenant || create!(:use_config_for_attributes => true) do |_|
      _log.info("Creating root tenant")
    end
  end

  # tenant
  #   tenant2
  #     project4 (!divisible)
  #   tenant3
  # @return [Array(Array<Array(String, Numeric)>, Array<Array(String, Numeric)>) ] tenants and projects
  #   e.g.:
  #   [
  #     [["tenant", 1], ["tenant/tenant2", 2]], ["tenant/tenant3", 3]]
  #     [["tenant/tenant2/project4", 4]]
  #   ]
  def self.tenant_and_project_names
    all_tenants_and_projects = Tenant.in_my_region.select(:id, :ancestry, :divisible, :use_config_for_attributes, :name)
    tenants_by_id = all_tenants_and_projects.index_by(&:id)

    tenants_and_projects = Rbac.filtered(Tenant.in_my_region.select(:id, :ancestry, :divisible, :use_config_for_attributes, :name))
                           .to_a.sort_by { |t| [t.ancestry || "", t.name] }

    tenants_and_projects.partition(&:divisible?).map do |tenants|
      tenants.map do |t|
        all_names = (t.ancestor_ids + [t.id]).map { |tid| tenants_by_id[tid] }.map(&:name)
        [all_names.join("/"), t.id]
      end.sort_by(&:first)
    end
  end

  #   Tenant
  #      Tenant A
  #      Tenant B
  #
  # @return [Array(JSON({name => String, id => Numeric, parent => Numeric}))] all subtenants of a tenant
  # e.g.:
  #   [
  #     {name=>"Tenant A",id=>2,parent=>1},
  #     {name=>"Tenant B",id=>3,parent=>1}
  #   ]
  def build_tenant_tree
    data_tenant = []
    all_subtenants.each do |subtenant|
      next unless subtenant.parent_name == name
      data_tenant.push(:name => subtenant.name, :id => subtenant.id, :parent => id)
      if subtenant.all_subtenants.count > 0
        data_tenant.concat(subtenant.build_tenant_tree)
      end
    end
    data_tenant
  end

  def allowed?
    Rbac::Filterer.filtered_object(self).present?
  end

  def create_users_group
    group = miq_groups.build(description: "g_#{external_id}", long_description: 'Default')
    group.miq_user_role = MiqUserRole.find_by_name("ICDC-user")
    group.save!
  end

  private

  # when a root tenant has an attribute with a nil value,
  #   read the value from the configurations table instead
  #
  # @return the attribute value
  def tenant_attribute(attr_name, setting_name)
    if use_config_for_attributes?
      ret = ::Settings.server[setting_name]
      block_given? ? yield(ret) : ret
    else
      self[attr_name]
    end
  end

  def nil_blanks
    self.subdomain = nil unless subdomain.present?
    self.domain = nil unless domain.present?

    self.name = nil unless name.present?
  end

  # validates that there is only one tree
  def validate_only_one_root
    unless parent_id || parent
      root = self.class.root_tenant_without_cache
      errors.add(:parent, "required") if root && root != self
    end
  end

  def create_tenant_group
    update_attributes!(:default_miq_group => MiqGroup.create_tenant_group(self)) unless default_miq_group_id
    self
  end

  def ensure_can_be_destroyed
    raise _("A tenant with groups associated cannot be deleted.") if miq_groups.non_tenant_groups.exists?
    raise _("A tenant created by tenant mapping cannot be deleted") if source
  end

  def validate_default_tenant
    if default_miq_group.tenant_id != id || !default_miq_group.tenant_group?
      errors.add(:default_miq_group, "default group must be a default group for this tenant")
    end
  end
end
