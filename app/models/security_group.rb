class SecurityGroup < ApplicationRecord
  include NewWithTypeStiMixin
  include SupportsFeatureMixin
  include CloudTenancyMixin
  include CustomActionsMixin

  acts_as_miq_taggable

  belongs_to :ext_management_system, :foreign_key => :ems_id, :class_name => "ManageIQ::Providers::NetworkManager"
  belongs_to :cloud_network
  belongs_to :cloud_tenant
  belongs_to :orchestration_stack
  belongs_to :network_group
  belongs_to :cloud_subnet
  belongs_to :network_router
  belongs_to :resource_group
  has_many   :firewall_rules, :as => :resource, :dependent => :destroy

  has_many :network_port_security_groups, :dependent => :destroy
  has_many :network_ports, :through => :network_port_security_groups
  # TODO(lsmola) we should be able to remove table security_groups_vms, if it's unused now. Can't be backported
  has_many :vms, -> { distinct }, :through => :network_ports, :source => :device, :source_type => 'VmOrTemplate'

  virtual_total :total_vms, :vms

  def self.non_cloud_network
    where(:cloud_network_id => nil)
  end

  def self.class_by_ems(ext_management_system)
    # TODO: use a factory on ExtManagementSystem side to return correct class for each provider
    ext_management_system && ext_management_system.class::SecurityGroup
  end

  def add_firewall_rule(data = nil)
    %i[direction security_group_id].each do |param|
      raise "Required parameter '#{param}' was not found" unless data[param.to_s]
    end
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    rule = network_service.security_groups.get(self.ems_ref).security_group_rules.new(data)
    rule.save
    self.ext_management_system.refresh_ems
  end

  def remove_firewall_rule(data = nil)
    raise ArgumentError.new("No arguments match") unless data
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    rule = network_service.security_groups.get(self.ems_ref).security_group_rules.get(data)
    rule.destroy
    self.ext_management_system.refresh_ems
  end

  def assigned_vms
    network_ports.collect { |port| port.device&.vm }
                  .map { |vm| vm.nics }
                  .map { |nic| { 
                    :nic => nic.first.name, 
                    :nicId => nic.first.uid_ems, 
                    :ipv4 => nic.first.network&.ipaddress, 
                    :ipv6 => nic.first.network&.ipv6address, 
                    :mac => nic.first.address, 
                    :vmName => nic.first.vm&.name, 
                    :vmId => nic.first.vm&.uid_ems, 
                    :serviceName => nic.first.vm&.service&.name 
                  } }
  end
end
