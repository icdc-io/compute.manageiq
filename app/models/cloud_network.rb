require 'ipaddr'

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
    network = network_service.networks.new(:name => "#{Icdc::Account::User.prefix(User.current_user)}#{data["name"]}", :mtu => '1500')
    ext_management_system.refresh_ems
    refresh_wait(network.id)
    network.id
  end

  def edit_network(net_id, data = nil)
    raise ArgumentError.new("Must specify data for editing resource") unless data
    network_service = ext_management_system.openstack_handle.detect_network_service
    network = network_service.update_network(net_id, {:name => data["name"]})
    ext_management_system.refresh_ems
  end

  def self.add_subnet(id, net_id, data)
    ext_management_system = ExtManagementSystem.find_by(:id => id)
    subnet_name = data.dig("name")
    data["name"] = "#{Icdc::Account::User.prefix(User.current_user)}#{subnet_name}"
    data["enable_dhcp"] = true
    cidr = IPAddr.new(data["cidr"])
    data["gateway_ip"] = IPAddr.new(cidr.to_i + 1, Socket::AF_INET).to_s
    data["cidr"] = "#{cidr.to_s}/#{cidr.prefix}"
    # subnet_id = network_service.create_subnet(opts["network_id"], opts["subnet"]["cidr"], 4, {:name => "#{account_name}_#{opts["type"]}", :enable_dhcp => opts["subnet"]["dhcp"], :gateway_ip => opts["subnet"]["gateway"]}).data.dig(:body, "subnet", "id")
    network_service = ext_management_system.openstack_handle.detect_network_service
    subnet = network_service.networks.find_by_id(net_id).subnets.create(data)
    router = network_service.routers.select { |router| router.name =~ /#{Icdc::Account::User.prefix(User.current_user)}/ }.first
    network_service.add_router_interface(router.id, subnet.id)
    ext_management_system.refresh_ems
  end

  def edit_subnet(net_id, data)
    network_service = ext_management_system.openstack_handle.detect_network_service
    network = network_service.networks.find_by_id(net_id)
    if data["subnet"]
      data["subnet"]["network_id"] = net_id
      if network.subnets.first
        subnet_id = network.subnets.first.id
        network.subnets.create(data["subnet"]) if network_service.delete_subnet(subnet_id)
      else
        network.subnets.create(data["subnet"])
      end
    elsif !network.subnets.empty?
      network_service.delete_subnet(network.subnets.first.id)
    end
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

  def delete_network
    network_service = ext_management_system.openstack_handle.detect_network_service
    network_service.delete_network(self.ems_ref)
    destroy!
    ext_management_system.refresh_ems
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
