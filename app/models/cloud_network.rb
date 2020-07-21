class CloudNetwork < ApplicationRecord
  include NewWithTypeStiMixin
  include SupportsFeatureMixin
  include CloudTenancyMixin
  include CustomActionsMixin
  include CustomAttributeMixin

  ALLOWED_CUSTOM_ATTRIBUTES = %w(description)

  acts_as_miq_taggable

  belongs_to :ext_management_system, :foreign_key => :ems_id, :class_name => "ManageIQ::Providers::NetworkManager"
  belongs_to :cloud_tenant
  belongs_to :orchestration_stack
  belongs_to :resource_group

  has_many :cloud_subnets, :dependent => :destroy
  has_many :network_routers, -> { distinct }, :through => :cloud_subnets
  has_many :public_networks, -> { distinct }, :through => :cloud_subnets
  has_many :network_ports, -> { distinct }, :through => :cloud_subnets
  has_many :floating_ips,  :dependent => :destroy
  has_many :vms, -> { distinct }, :through => :network_ports, :source => :device, :source_type => 'VmOrTemplate'

  has_many :public_network_routers, :foreign_key => :cloud_network_id, :class_name => "NetworkRouter"
  has_many :public_network_vms, -> { distinct }, :through => :public_network_routers, :source => :vms
  has_many :private_networks, -> { distinct }, :through => :public_network_routers, :source => :cloud_networks

  # TODO(lsmola) figure out what this means, like security groups used by VMs in the network? It's not being
  # refreshed, so we can probably delete this association
  has_many   :security_groups

  # Use for virtual columns, mainly for modeling array and hash types, we get from the API
  serialize :extra_attributes

  virtual_column :maximum_transmission_unit, :type => :string
  virtual_column :port_security_enabled,     :type => :string
  virtual_column :qos_policy_id,             :type => :string

  # Define all getters and setters for extra_attributes related virtual columns
  %i(maximum_transmission_unit port_security_enabled qos_policy_id).each do |action|
	  define_method("#{action}=") do |value|
      extra_attributes_save(action, value)
    end

    define_method(action) do
      extra_attributes_load(action)
    end
  end

  virtual_total :total_vms, :vms

  def self.class_by_ems(ext_management_system, _external = false)
    # TODO: A factory on ExtManagementSystem to return class for each provider
    ext_management_system && ext_management_system.class::CloudNetwork
  end

  def self.tenant_id_clause_format(tenant_ids)
    ["((tenants.id IN (?) OR cloud_networks.shared IS TRUE OR cloud_networks.external_facing IS TRUE) AND ext_management_systems.tenant_mapping_enabled IS TRUE) OR ext_management_systems.tenant_mapping_enabled IS FALSE OR ext_management_systems.tenant_mapping_enabled IS NULL", tenant_ids]
  end

  def self.create_network(id, data = nil)
    raise ArgumentError.new("No arguments match") unless data
    ext_management_system = ExtManagementSystem.find_by(:id => id)
    network_service = ext_management_system.openstack_handle.detect_network_service
    network = network_service.create_network(:name => data["name"])
    network_id = network[:body]["network"]["id"]
    ext_management_system.refresh_ems
    refresh_wait(network_id)
    CloudNetwork.find_by(:ems_ref => network_id).add_description({'description' => data["description"]})
    network_id
  end

  def self.add_subnet(id, net_id, data)
    ext_management_system = ExtManagementSystem.find_by(:id => id)
    network_service = ext_management_system.openstack_handle.detect_network_service
    network_service.networks.find_by_id(net_id).subnets.create(data)
    ext_management_system.refresh_ems
  end

  def self.refresh_wait(network_id)
    CloudNetwork.uncached do
      30.times do
        network = CloudNetwork.find_by(:ems_ref => network_id)
        if network
          break
        else
          sleep 2
          next
        end
      end
    end
  end

  def add_description(data)
    ALLOWED_CUSTOM_ATTRIBUTES.each{|attr| self.miq_custom_set(attr, data[attr])}
  rescue => e
    _log.error("Unable to set custom attributes for network #{self}: #{e}")
  end

  private

  def extra_attributes_save(key, value)
    self.extra_attributes = {} if extra_attributes.blank?
    self.extra_attributes[key] = value
  end

  def extra_attributes_load(key)
    self.extra_attributes[key] unless extra_attributes.blank?
  end
end
