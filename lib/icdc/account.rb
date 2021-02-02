module Icdc
  module Account

    class User
      def self.register(params)
        user = ::User.new
        user.userid = params[:user_name]
        user.email = params[:user_name]
        user.name = "#{params[:user_firstname]} #{params[:user_lastname]}"
        tenants = default_tenants(user)
        # By default we assign member role for all accounts
        user.miq_groups = tenants.map do |tenant|
          tenant.miq_groups.detect{ |group| group.name.end_with?(".member") }
	      end
	      user.save!

        # Sync User objects to child regions if configured
        tenants.each do |tenant|
          next if tenant.regional_tenants.count <= 1 # no child regions for this tenant
          regions = tenant.regional_tenants.collect { |d| d.region.description }
          args = (regions + [ user.userid ]).join('_').to_s
          %x[rake users_sync:sync_user[#{args}]]
        end
        user
      end

      def self.default_tenants(user)
        [
          Lotus.new.get_account(user),
          Tenant.in_my_region.where(:name => "Demo").first
        ].compact
      end
    end

    class Lotus
      require 'net/http'
      require 'json'
      require 'apipie-bindings'
      attr_reader :logger, :config, :conn

      def initialize
        @logger = Logger.new(File.join(Rails.root, "log", "lotus.log"))
        @config = YAML.load_file(File.join(Rails.root, "config", "lotus.yml"))
        @conn = ApipieBindings::API.new({:uri => @config[:url], :timeout => 5})
      end

      def get_account(username)
        user = conn.resource(:users).call(:index, :key => config[:api_key], :filter => {:mail => username}).deep_symbolize_keys
        logger.debug("Lotus Employee object for #{username}: #{user.inspect}")
        department_id = user[:data].first[:relationships][:department][:data][:id]
        department = conn.resource(:departments).call(:show, :key => config[:api_key], :id => department_id).deep_symbolize_keys
        logger.debug("Lotus Department object for #{username}: #{department.inspect}")
        # account is an 'IBA department', so it located at second field from the top structure
        account_id = department[:data][:attributes][:path].second
        account = conn.resource(:departments).call(:show, :key => config[:api_key], :id => account_id).deep_symbolize_keys
        logger.debug("Lotus Department object for account: #{account.inspect}")
        account_name = account[:data][:attributes][:name]
        account_tenant = Tenant.in_my_region.where(:description => account_name).first
        logger.info("Lotus #{username} is an IBA employee. Account: #{account_tenant.inspect}")
        account_tenant
      rescue => e
        logger.info("Lotus #{username} is not IBA employee. Error: #{e.message}")
        nil
      end

    end

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

      def create_cloud_tenant(name)
        miq_tenant = Tenant.find_by(:name => name)
        cloud_tenant = CloudTenant.create(:name => name, :description => miq_tenant.description)
        miq_tenant.source_type = 'CloudTenant'
        miq_tenant.source_id = cloud_tenant.id
        miq_tenant.save!
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
        crd.create_cloud_tenant(account_name)
        return unless crd.network_service
        resources = crd.config.dig("resources")
        resources.dig("routers").each{ |name| crd.create_router(name) }
        resources.dig("networks").each { |network_config| crd.create_network(network_config) }
      end

    end # Class Infrastructure

  end # module Account

end #module Icdc
