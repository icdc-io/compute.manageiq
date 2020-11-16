require 'net/http'
require 'base64'
require 'json'
require 'openssl'
require 'ipaddr'

class HaproxyCluster < ApplicationRecord
  def self.get_proxy_server(service)
    location_name = service.miq_region.description.downcase
    account = service.tenant.project? && service.tenant.parent || service.tenant
    account_name = account.name.downcase.slice(0..4)
    HaproxyCluster.in_region(service.region_number).find_by(:name => "#{location_name}_#{account_name}_default") ||
    HaproxyCluster.in_region(service.region_number).first # legacy for IDC/NB5
  end

  def self.create_proxy_server(params)
    cluster = HaproxyCluster.new
    cluster.name = params["name"]
    cluster.hostname = params["hostname"]
    cluster.api_key = params["api_key"]
    cluster.save
  end

  def get_service_routes(object)
    conn = connection
    request = get_request("/api/1/routes?service=#{object.id}")
    response = conn.request(request)
    HaproxyRoute.show(response.body)
  end

  def get_service_route(_object, id)
    conn = connection
    request = get_request("/api/1/routes/#{id}")
    response = conn.request(request)
    HaproxyRoute.show(response.body)
  end

  def add_service_routes(object, data)
    body = generate_body(object, data)
    conn = connection
    request = post_request("/api/1/routes", body)
    response = conn.request(request)
    response
  end

  def edit_service_routes(object, data)
    body = generate_body(object, data)
    conn = connection
    request = put_request("/api/1/routes/#{data["route_id"]}", body)
    response = conn.request(request)
    response
  end

  def delete_service_routes(_object, data)
    data = data.symbolize_keys

    conn = connection
    request = get_request("/api/1/routes/#{data[:route_id]}")
    response = conn.request(request)
    haproxy_config = response.body

    request = delete_request("/api/1/routes/#{data[:route_id]}")
    response = conn.request(request)
    response
  end

  def suspend_service_route(_object, id)
    conn = connection
    request = put_request("/api/1/routes/#{id}/suspend", {})
    response = conn.request(request)
    response
  end

  def get_certificates
    conn = connection
    request = get_request("/api/1/certs?owner=#{User.current_user.userid}")
    conn.request(request)
  end

  def add_certificate(_object, data)
    data[:owner] = User.current_user.userid

    data["cert"] = data["cert"]["base64"]

    data["key"] =
      data["key"] ? data["key"]["base64"] : ''

    data["ca"] =
      data["ca"] ? data["ca"]["base64"] : ''

    conn = connection
    request = post_request("/api/1/certs", data)
    response = conn.request(request)
    response
  end

  def delete_certificate(_object, data)
    conn = connection
    request = delete_request("/api/1/certs/#{data["cert_id"]}")
    response = conn.request(request)
    response
  end

  def check_certificate(domain)
    conn = connection
    request = get_request("/api/1/certs?domain=#{domain}")
    conn.request(request)
  end

  def routes
    conn = connection
    request = get_request("/api/1/routes")
    conn.request(request)
  end

  private

  def connection
    uri = URI.parse(hostname)
    http = Net::HTTP.new(uri.host, uri.port)
    http
  end

  def get_request(url)
    request = Net::HTTP::Get.new(url)
    request.add_field("X_HAPROXYAPI_KEY", api_key)
    request
  end

  def post_request(url, body)
    request = Net::HTTP::Post.new(url)
    request.add_field("X_HAPROXYAPI_KEY", api_key)
    request.body = body.to_json
    request
  end

  def put_request(url, body)
    request = Net::HTTP::Put.new(url)
    request.add_field("X_HAPROXYAPI_KEY", api_key)
    request.body = body.to_json
    request
  end

  def delete_request(url)
    request = Net::HTTP::Delete.new(url)
    request.add_field("X_HAPROXYAPI_KEY", api_key)
    request
  end

  def generate_body(object, data)
    data = data.deep_symbolize_keys
    body = {
      "name"           => data[:name],
      "host"           => data[:dns],
      "proto"          => data[:externalProtocol].downcase,
      "service_id"     => object.id,
      "approve_status" => "approved",
      "project"        => data[:project],
      "security"       => {
        "status"  => "approved",
        "purpose" => data[:purpose],
        "project" => {
          "code"    => data[:project][:code],
          "name"    => data[:project][:name],
        }
      },

      "backend"        => {
        "balance" => "roundrobin",
        "proto"   => data[:internalProtocol].downcase,
        "servers" => [],
      },
    }

    data[:vms].each do |vm|
      raise "Wrong or private IP address #{vm[:host]}" unless ip_allowed(object, vm[:host])
      server = {"name" => vm[:id], "host" => vm[:host], "port" => data[:port]}
      body["backend"]["servers"].push(server)
    end
    _log.info("Haproxy body: #{body.inspect}")
    body
  end

  def public_subnets(service)
    @public_subnets ||= begin
      service.networks
        .reject{|n| n.name.match?(/^\w{3}_vl_/)} # Reject Foreman private VLAN
        .map{|n| n.network_address || n.cidr}.compact # network_address = Foreman, cidr = OVN
        .map{|addr| IPAddr.new(addr)}
    end
  end

  def ip_allowed(object, ip)
    public_subnets(object).find { |s| s.include?(ip) } || 
    ip&.match?(/10.211.0.[0..9]*/) # FIX: it someday. This is workaround for PowerSystem in SBG
  end
end
