require 'ostruct'
require 'rest-client'

module Icdc::Foreman
  class Subnet < OpenStruct
    def as_json(options = nil)
      @table.as_json(options)
    end

    def set_parameter(param_name, param_value)
      payload = {:parameter => {:name => param_name, :value => param_value}}
      if parameter_exists(param_name)
        p = parameters.select { |param| param['name'] == param_name }
        connection.put("/api/subnets/#{id}/parameters/#{p.first['id']}", payload)
      else
        connection.post("/api/subnets/#{id}/parameters", payload)
      end
    end

    def parameter_exists(param)
      parameters.find { |parameter| parameter['name'] == param } ? true : false
    end
  end

  class SmartProxy < OpenStruct
    include Vmdb::Logging
    DEFAULT_TIMEOUT = 3

    def as_json(options = nil)
      {}.as_json(options) # hide sensitive info
    end

    def initialize(config, hash)
      super(hash)
      @cert = OpenSSL::X509::Certificate.new(File.read(config[:cert]))
      @key = OpenSSL::PKey::RSA.new(File.read(config[:key]), "passphrase, if any")
      @base_url = "#{url}/dhcp"
      @verify_ssl = config[:skip_verify_smartproxy] ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
      @timeout = config[:timeout] || DEFAULT_TIMEOUT
    end

    def ip_allocations(subnet, macs)
      if macs.count > 1
        allocs = get("/#{subnet.network}")
        return [] if allocs.nil?

        allocs = allocs["reservations"].select { |a| macs.include?(a["mac"].downcase) }
      else
        allocs = [get("/#{subnet.network}/#{macs.first.downcase}")].compact
      end
      allocs.map do |alloc|
        os_alloc = OpenStruct.new(alloc)
        os_alloc.subnet = subnet.name # reference to subnet
        os_alloc
      end
    end

    private

    def get(path)
      res = RestClient::Request.execute(
        :method          => :get,
        :url             => @base_url + path,
        :ssl_client_cert => @cert,
        :ssl_client_key  => @key,
        :verify_ssl      => @verify_ssl,
        :timeout         => @timeout,
      )
      JSON.parse(res)
    rescue RestClient::NotFound
      _log.info("Smartproxy record #{@base_url + path} was not found")
      nil
    rescue StandardError => e
      _log.error("Foreman request #{@base_url + path} failed with error #{e.message}")
      nil
    end
  end

  class Client
    include Vmdb::Logging
    CONFIG = YAML.load_file(Rails.root.join('config', 'foreman.yml'))

    def initialize(region)
      @config = CONFIG[region]
    end

    def ready?
      @config.present?
    end

    def subnets(names)
      return [] unless ready?
      subnets = []
      tasks = parallel(names) { |name| subnet(name) }
      process(tasks) do |net|
        subnets << net if net
      end
      subnets
    end

    def ip_allocations(subnet_macs)
      return [] unless ready?
      allocs = []
      tasks = parallel(subnet_macs) do |entry|
        entry[:subnet].dhcp.ip_allocations(entry[:subnet], entry[:macs])
      end
      process(tasks) do |subnet_allocs|
        allocs.push(*subnet_allocs)
      end
      allocs
    end

    def free_ips(subnets)
      return [] unless ready?
      ips = []
      tasks = parallel(subnets) { |subnet| free_ip(subnet) }
      process(tasks) do |ip|
        ips << ip if ip
      end
      ips
    end

    def get(path)
      res = RestClient::Request.execute(
        :method     => :get,
        :url        => @config[:foreman_url] + path,
        :user       => @config[:user],
        :password   => @config[:password],
        :verify_ssl => @config[:skip_verify] ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER,
      )
      JSON.parse(res)
    rescue RestClient::NotFound
      _log.info("Foreman subnet #{@config[:foreman_url] + path} not found")
      nil # not an error
    rescue StandardError => e
      _log.error("Foreman request to #{@config[:foreman_url] + path} failed with error: #{e.message}")
      nil
    end

    def put(path, payload)
      res = RestClient::Request.execute(
        :method     => :put,
        :url        => @config[:foreman_url] + path,
        :user       => @config[:user],
        :password   => @config[:password],
        :verify_ssl => @config[:skip_verify] ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER,
        :payload    => payload.to_json,
        :headers    => {
          :content_type => :json,
          :accept       => :json
        }
      )
      JSON.parse(res)
    rescue RestClient::NotFound
      _log.info("Foreman subnet #{@config[:foreman_url] + path} not found")
      nil # not an error
    rescue StandardError => e
      _log.error("Foreman request to #{@config[:foreman_url] + path} failed with error: #{e.message}")
      nil
    end

    def post(path, payload)
      res = RestClient::Request.execute(
        :method     => :post,
        :url        => @config[:foreman_url] + path,
        :user       => @config[:user],
        :password   => @config[:password],
        :verify_ssl => @config[:skip_verify] ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER,
        :payload    => payload.to_json,
        :headers    => {
          :content_type => :json,
          :accept       => :json
        }
      )
      JSON.parse(res)
    rescue RestClient::NotFound
      _log.info("Foreman subnet #{@config[:foreman_url] + path} not found")
      nil # not an error
    rescue StandardError => e
      _log.error("Foreman request to #{@config[:foreman_url] + path} failed with error: #{e.message}")
      nil
    end

    private

    def parallel(items)
      q = Queue.new
      items.each { |item| q << item }
      threads = []
      items.size.times.each do
        threads << Thread.new do
          Thread.current[:data] = yield(q.pop)
        end
      end
      threads
    end

    def process(threads)
      threads.map do |t|
        t.join
        yield(t[:data])
      end
    end

    def subnet(name)
      subnet = Subnet.new(get("/api/subnets/#{name}"))
      subnet.dhcp = SmartProxy.new(@config, subnet.dhcp) if subnet.dhcp
      subnet.dns = SmartProxy.new(@config, subnet.dns) if subnet.dns
      subnet
    end

    def free_ip(subnet)
      ip = get("/api/subnets/#{subnet}/freeip")["freeip"]
      { :subnet => subnet, :ip => ip }
    end
  end

  class Organization < OpenStruct
    include Vmdb::Logging

    def initialize(region:, tenant_name:)
      %i[region tenant_name].each do |param|
        raise ArgumentError, "Required parameter #{param} not found" unless param
      end
      @foreman_client = Icdc::Foreman::Client.new(region)
      if ready?
        org_data = @foreman_client.get("/api/organizations/#{tenant_name}")
        super(org_data)
        fetch_tenant_subnets
      end      
    end

    def ready?
      @foreman_client.ready?
    end

    def get_subnets(filters = {})
      return [] unless ready?
      result = subnets
      filters.each do |param_name, param_value|
        result = result.select do |subnet|
          founded = subnet.parameters.find { |param| param['name'] == param_name.to_s }
          founded && founded['value'].downcase == param_value
        end
      end
      result.each { |subnet| subnet.connection = @foreman_client }
      result
    end

    def assign_subnet(name)
      return [] unless ready?
      payload = {:organization => {:name => self.name}, :subnets => []}
      subnets.each { |subnet| payload[:subnets] << {:name => subnet.name} }
      payload[:subnets] << {:name => name}
      response = @foreman_client.put("/api/organizations/#{id}", payload)
      if response['subnets'].find { |subnet| subnet['name'] == name }
        self.subnets = response['subnets']
      end
      fetch_tenant_subnets
    end

    private

    def fetch_tenant_subnets
      subnets = [] unless subnets
      subnets_list = subnets.map { |subnet| subnet['name'] }
      self.subnets = @foreman_client.subnets(subnets_list)
    end
  end
end
