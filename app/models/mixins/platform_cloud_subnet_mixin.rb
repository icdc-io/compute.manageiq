module PlatformCloudSubnetMixin
  def assigned_ips
    ns = ext_management_system.openstack_handle.detect_network_service
    ports = ns.ports.select { _1.network_id == cloud_network.ems_ref }
    ports.map { _1.fixed_ips.dig(0, 'ip_address') }
  end
end
