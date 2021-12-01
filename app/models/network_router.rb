class NetworkRouter < ApplicationRecord
  include NewWithTypeStiMixin
  include SupportsFeatureMixin
  include CloudTenancyMixin
  include CustomActionsMixin

  acts_as_miq_taggable

  belongs_to :ext_management_system, :foreign_key => :ems_id, :class_name => "ManageIQ::Providers::NetworkManager"
  belongs_to :cloud_tenant
  belongs_to :network_group
  belongs_to :cloud_network

  has_many :cloud_subnets
  has_many :network_ports, -> { distinct }, :through => :cloud_subnets
  has_many :vms, -> { distinct }, :through => :cloud_subnets

  has_many :floating_ips, :through => :cloud_network
  has_many :cloud_networks, -> { distinct }, :through => :cloud_subnets
  has_many :security_groups, :dependent => :nullify

  alias private_networks cloud_networks
  alias public_network cloud_network

  # Use for virtual columns, mainly for modeling array and hash types, we get from the API
  serialize :extra_attributes

  virtual_column :external_gateway_info, :type => :string # :hash
  virtual_column :distributed          , :type => :boolean
  virtual_column :routes               , :type => :string # :array
  virtual_column :propagating_vgws     , :type => :string # :array
  virtual_column :main_route_table     , :type => :boolean # :array
  virtual_column :high_availability    , :type => :boolean

  # Define all getters and setters for extra_attributes related virtual columns
  %i(external_gateway_info distributed routes propagating_vgws main_route_table high_availability).each do |action|
    define_method("#{action}=") do |value|
      extra_attributes_save(action, value)
    end

    define_method(action) do
      extra_attributes_load(action)
    end
  end

  virtual_total :total_vms, :vms

  def self.class_by_ems(ext_management_system)
    # TODO: use a factory on ExtManagementSystem side to return correct class for each provider
    ext_management_system && ext_management_system.class::NetworkRouter
  end

  def assign_route(data = nil)
   raise RuntimeError.new("You can't create identical routes") unless routes.select { |route| route["nexthop"] == data["nexthop"] && route["destination"] == data["destination"] }.empty?
   raise ArgumentError.new("No arguments match") unless data
   network_service = self.ext_management_system.openstack_handle.detect_network_service
   ns_routes = network_service.get_router(self.ems_ref)[:body]["router"]["routes"]
   ns_routes << data
   update!(:routes => ns_routes)
   network_service.update_router(self.ems_ref, {:routes => ns_routes})
   self.ext_management_system.refresh_ems
  end

  def remove_route(data = nil)
    raise ArgumentError.new("No arguments match") unless data
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    ns_routes = network_service.get_router(self.ems_ref)[:body]["router"]["routes"]
    ns_routes.delete_if { |route| route["destination"] == data["destination"] }
    update!(:routes => ns_routes)
    network_service.update_router(self.ems_ref, {:routes => ns_routes})
    self.ext_management_system.refresh_ems
  end

  def edit_route(data = nil)
    raise ArgumentError.new("No arguments match") unless data
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    routes = network_service.get_router(self.ems_ref)[:body]["router"]["routes"]

    if data["oldDestination"] === data["newRoute"]["destination"]
      routes.delete_if { |route| route["destination"] == data["oldDestination"] }
      routes << data["newRoute"]
    else
      if routes.find { |route| route["destination"] == data["newRoute"]["destination"] }
        raise RuntimeError.new("The route with destination #{data["newRoute"]["destination"]} already exists")
      else
        routes.delete_if { |route| route["destination"] == data["oldDestination"] }
        routes << data["newRoute"]
      end
    end

    network_service.update_router(self.ems_ref, {:routes => routes})
    self.ext_management_system.refresh_ems
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
