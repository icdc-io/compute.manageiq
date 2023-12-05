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

  virtual_column :assigned_vms,     :type => :string

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

  def self.force_push(ems_id, group_name)
    ems = ExtManagementSystem.find_by(:id => ems_id)
    network_service = ems&.openstack_handle.detect_network_service
    raise RunTimeError.new("Network service didn't detected") unless network_service
    ovn_groups_ids = network_service.security_groups.select { |group| group.name == group_name }.collect(&:id)
    new_group_id = ovn_groups_ids.reject{ |id| !SecurityGroup.find_by(:ems_ref => id).nil? }[0]
    return unless new_group_id
    SecurityGroup.create(:name => group_name, :cloud_tenant => User.current_user.current_tenant.source, :ems_ref => new_group_id, :type => SecurityGroup.class_by_ems(ems).to_s, :ems_id => ems.id)
    ems&.refresh_ems
  end

  def add_firewall_rule(data = nil)
    %i[direction security_group_id].each do |param|
      raise "Required parameter '#{param}' was not found" unless data[param.to_s]
    end
    ethertype_mapper = {"ipv4" => "IPv4", "ipv6" => "IPv6", nil => "", "" => ""}
    ethertype = ethertype_mapper[data["network_protocol"]&.downcase]
    # ahrechushkin:  cause we have different terms in OVN and fog
    remote_ip_prefix = nil
    if data["source_ip_range"] && data["source_ip_range"] != ""
      source_ip_range = IPAddr.new(data["source_ip_range"])
      remote_ip_prefix = "#{source_ip_range.to_s}/#{source_ip_range.prefix}"
    end
    data.merge!({"ethertype" => ethertype, "remote_ip_prefix" => remote_ip_prefix})
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    begin
      rule = network_service.security_groups.get(self.ems_ref).security_group_rules.new(data)
      rule.save
    rescue => e
      err_msg = JSON.parse(e.response.body).dig("error", "message")
      return {:success => 'false', :message => "#{error_parser(err_msg)}"}
    end
    force_push_new_rule(rule.id, data)
    self.ext_management_system.refresh_ems
    return {:success => 'true', :message => 'Rule was added successfully'}
  end

  def remove_firewall_rule(data = nil)
    raise ArgumentError.new("No arguments match") unless data
    _log.info("ahrechushkin debug rm fwr #{data}")
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    FirewallRule.find_by(:ems_ref => data).destroy!
    rule = network_service.security_groups.get(self.ems_ref).security_group_rules.get(data)
    rule.destroy
    self.ext_management_system.refresh_ems
  end

  def edit_firewall_rule(data = nil)
    # TODO: this operation is not stable now and needs refactoring
    raise ArgumentError.new("No arguments match") unless data
    network_service = self.ext_management_system.openstack_handle.detect_network_service
    security_group_rules = network_service.security_groups.get(self.ems_ref).security_group_rules
    newRule = security_group_rules.new(data.except('id'))
    oldRule = security_group_rules.get(data['id'])

    duplicates = security_group_rules.find_all { |i| i.attributes.with_indifferent_access === data }
    raise RuntimeError.new("Can not save duplicated rule!") if duplicates.length > 0

    newRule.save
    oldRule.destroy
    self.ext_management_system.refresh_ems
  end

  def assigned_vms
    network_ports.where(:device_type => "GuestDevice").map do |port|
      nic = port.device
      network = nic.network
      vm = nic.vm
      service = vm&.service
      {
        :nic         => nic.name,
        :nicId       => nic.uid_ems,
        :mac         => nic.address,
        :ipv4        => network&.ipaddress,
        :ipv6        => network&.ipv6address,
        :vmName      => vm&.name,
        :vmId        => vm&.uid_ems,
        :serviceName => service&.name,
        :email       => service&.evm_owner_email
      }
    end
  end

  def add_to_port(data)
    ns = ext_management_system.openstack_handle.detect_network_service
    data["nic_ids"].each do |nic_id|
      port_id = ns.ports.select{|x| x.device_id == nic_id}.first.id
      network_ports.push(NetworkPort.find_by(:ems_ref => port_id))
      ns.update_port(port_id, {:security_groups => ns.ports.find_by_id(port_id).security_groups.push(ems_ref)})
      rescue RuntimeError => e
        next
    end
  end

  def remove_from_port(data)
    ns = ext_management_system.openstack_handle.detect_network_service
    nic_id = data["nic_id"]
    port_id = ns.ports.select{|x| x.device_id == nic_id}.first.id
    network_ports.delete(NetworkPort.find_by(:ems_ref => port_id))
    ns.update_port(port_id, {:security_groups => ns.ports.find_by_id(port_id).security_groups - [ems_ref]})
  end

  def force_push_new_rule(rule_uid, data)
    direction_mapper = { "ingress" => "inbound", "egress" => "outbound" }
    sg_id = SecurityGroup.find_by(:ems_ref => data["remote_group_id"])&.id
    fw_rule = FirewallRule.new(:host_protocol => data["protocol"]&.upcase,
                               :direction => direction_mapper[data["direction"]],
                               :port => data["port_range_min"],
                               :end_port => data["port_range_max"],
                               :ems_ref => rule_uid,
                               :source_ip_range => data["source_ip_range"],
                               :source_security_group_id => sg_id,
                               :resource_id => id,
                               :resource_type => "SecurityGroup",
                               :network_protocol => data["network_protocol"].downcase)
    fw_rule.save
  end

  private

  def error_parser(msg)
    return "Rule already exists" if msg.downcase.match?(/already exists/)
    return msg if msg.downcase.match?(/only [^\>]* may be provided/)
    "Something went wrong"
  end
end
