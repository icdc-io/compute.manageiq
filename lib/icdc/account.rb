module Icdc
  module Account

    class CRD
      attr_reader :account_name, :config, :network_service

      def initialize(account_name = nil)
        region = MiqRegion.my_region.description.downcase 
        @account_name = "#{region}_#{account_name.downcase}"       
        @config = load_config
        manager = ExtManagementSystem.where(:type => "ManageIQ::Providers::Redhat::NetworkManager").first
        @network_service = manager.openstack_handle.detect_network_service if manager
      end

      def load_config
        YAML.load_file(File.join(Rails.root, "config/account_crd.yml"))
      rescue Errno::ENOENT => e
        raise "File config/ovn_crd doesn't exist."
      end

      def create_router(router_name)
        network_service.create_router("#{account_name}_#{router_name}")
      end

      def create_network(network_config)
	      network_config.map do |type, opts|
	        network = network_service.networks.new(:name => "#{account_name}_#{type}", :mtu => opts['mtu'])
          network.save
          # CloudNetwork.refresh_wait(network.id)
          # CloudNetwork.find_by(:ems_ref => network.id).add_description({'description' => "#{account_name} #{type} network"})
          opts["network_id"] = network.id
          opts["type"] = type
          create_subnet(opts) if opts['subnet']
        end
      end

      private

      def create_subnet(opts)
        subnet_id = network_service.create_subnet(opts["network_id"], opts["subnet"]["cidr"], 4, {:name => "#{account_name}_#{opts["type"]}", :enable_dhcp => opts["subnet"]["dhcp"], :gateway_ip => opts["subnet"]["gateway"]}).data.dig(:body, "subnet", "id")
        router_id = network_service.routers.select { |router| router.name == "#{account_name}_#{opts["subnet"]["router"]}" }.first.id
        network_service.add_router_interface(router_id, subnet_id)
      end
    end # Class CRD

    class Infrastructure
      def self.build(account_name)
        crd = CRD.new(account_name)
        return unless crd.network_service
        resources = crd.config.dig("resources")
        resources.dig("routers").each{ |name| crd.create_router(name) }
        resources.dig("networks").each { |network_config| crd.create_network(network_config) }
      end

    end # Class Infrastructure

  end # module Account

end #module Icdc
