module Icdc
  class IpAllocation < OpenStruct
    def initialize(hash = nil)
      super(hash)
    end

    def as_json(options = {})
      # There is currently no attribute whitelist for IpAllocation
      # No sensitive data here
      @table.as_json(
        options.merge(
          :only => [
            :id,
            :hostname,
            :ip,
            :mac,
            :type, # virtual or nic
            :vm_id, # allocation assigned to VM
            :vm_name,
            :service_id # allocation assigned to VM
          ]
        )
      )
    end
  end

  class Network < OpenStruct
    def initialize(hash = nil)
      super(hash)
      parse_name_info(name)
    end

    def name=(name)
      @name = name
      parse_name_info(name)
    end

    def as_json(options = {})
      parameters_hash = {}
      parameters&.each { |p| parameters_hash[p["name"].to_sym] = p["value"] }
      # We need attribute whitelist here, because there is sensitive data:
      # DHCP addresses, DHCP ip range, Smartproxy IDs
      @table.as_json({
        :only => [
          :name, :network_address, :network, :cidr, :network_type,
          :mask, :gateway, :dns_primary, :dns_secondary,
        ]
      }.merge(options))
            .merge(:allocations => allocations.as_json)
            .merge(:parameters => parameters_hash.as_json)
    end

    def self.authorized_networks(service)
      nics = GuestDevice.where(
        :hardware_id => Hardware.where(
          :vm_or_template_id => service.vms.pluck(:id)
        ).pluck(:id)
      ).where.not(:lan_id => nil)
      # Get VirtualIp objects for this service and all child services
      vips = VirtualIp.where(:service_id => [service.id] + service.services.pluck(:id))
      # Prepare list of MACs in each logical network
      # {"idc_vl_2334" => [00:11:22:33:44:55, 66:77:88:99:00:11], "idc_pvl_2314" => [aa:bb:cc:dd:ee:ff]}
      net_nics = nics.group_by { |nic| nic.lan.name }
      net_macs = net_nics.map { |name, nic_arr| [name, nic_arr.map(&:address)] }.to_h
      vips.group_by(&:subnet).each do |name, vip_arr|
        net_macs[name] = (net_macs[name] || []) + vip_arr.map(&:mac)
      end
      # Reverse lookup - IP allocation to NIC
      net_mac_nics = net_nics.map do |net_name, nic_arr|
        [net_name, nic_arr.group_by(&:address)]
      end.to_h
      # Request authorized networks (CMDB DHCP records) for both: VM nics and service VIPs
      networks = fetch_networks(service, net_macs) do |alloc|
        nic = net_mac_nics.dig(alloc.subnet, alloc.mac)&.first
        if nic
          alloc.nic = nic
          alloc.type = :nic
          alloc.vm_id = nic.hardware.vm.id
          alloc.vm_name = nic.hardware.vm.name
        else
          vip = vips.where(:subnet => alloc.subnet, :mac => alloc.mac).first
          if vip
            alloc.type = :virtual
            alloc.service_id = vip.service_id
            alloc.id = vip.id
          end
        end
        alloc
      end
      networks
    end

    def self.fetch_networks(service, net_macs)
      # TODO: make it properly someday :)
      begin
        foreman_networks(service.region_id, net_macs) +  ovirt_networks(net_macs)
      rescue
        ovirt_networks(net_macs)
      end
    end

    def self.foreman_networks(foreman_id, net_macs)
      client = Icdc::Foreman::Client.new(foreman_id)
      subnets = client.subnets(net_macs.keys) # L2 net name == L3 subnet name in foreman for IPv4
                      .reject { |subnet| subnet.name.nil? } # L2 network has no equalent in Foreman
                      .reject { |subnet| subnet.dhcp.nil? } # L3 subnet is not managed by Foreman
                      .group_by(&:name)
                      .map { |name, subnet_arr| [name, subnet_arr&.first] }.to_h # name is unique
      subnet_macs_tuples = subnets.values.map do |subnet|
        {
          :subnet => subnet,
          :macs   => net_macs[subnet.name]
        }
      end
      client.ip_allocations(subnet_macs_tuples).group_by(&:subnet).map do |name, allocs|
        network = new(subnets[name])
        network.allocations = allocs.map do |alloc|
          yield(IpAllocation.new(alloc)) if block_given?
        end
        network
      end
    end

    def self.ovirt_networks(net_macs)
      net_macs.map do |net, macs|
        network_params = CloudNetwork.find_by(:name => net).cloud_subnets&.first
        network = new(network_params.as_json.merge!(:name => network_params.cloud_network.name))
        network.allocations = os_allocs(macs) do |alloc|
          yield(IpAllocation.new(alloc)) if block_given?
        end
        network
      end
    end

    def self.os_allocs(macs)
      macs.map do |mac|
        alloc = NetworkPort.find_by(:mac_address => mac)
        nic = {
          :hostname => '',
          :ip       => alloc.ipaddresses&.first,
          :mac      => alloc.mac_address
        }
        os_alloc = OpenStruct.new(nic)
        os_alloc.subnet = alloc.cloud_subnets&.first&.name
	os_alloc.type = :nic
        os_alloc
      end
    end

    def self.guest_networks(service)
      networks = {}
      service.vms.each do |vm|
        vm.hardware.networks.each do |netif|
          nic = nil
          net_name = "local:#{vm.name}" # net name for internal guest network interfaces
          if netif.device_id # real network interface
            nic = vm.hardware.nics.where(:id => netif.device_id).first
            next unless nic # bad record

            net_name = nic.lan.name if nic.lan
          end
          {"IPv4" => netif.ipaddress, "IPv6" => netif.ipv6address}.each do |_ip_type, ip|
            next unless ip

            alloc = IpAllocation.new(
              :hostname => netif.hostname,
              :ip       => ip,
              :mac      => nic&.address,
              :type     => :guest,
              :subnet   => net_name,
              :vm_id    => vm.id,
              :vm_name  => vm.name
            )
            get_or_create(networks, net_name).allocations << alloc
          end
        end
      end
      networks.values
    end

    def self.get_or_create(lookup, name)
      lookup[name] = new(:name => name, :allocations => []) unless lookup[name]
      lookup[name]
    end
    private_class_method :get_or_create

    private

    def parse_name_info(name)
      # Define additional info based on name
      location, _type, vlan = name.split('_', 3)
      @location = location.downcase.to_sym
      @vlan = vlan
    end
  end
end

