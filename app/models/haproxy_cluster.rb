require 'net/http'
require 'base64'
require 'json'
require 'openssl'
require 'ipaddr'

class HaproxyCluster < ApplicationRecord
  def self.get_proxy_server(service)
    region_number = service.region_number
    HaproxyCluster.in_region(region_number).first
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
    if response.kind_of?(Net::HTTPSuccess)
      user = User.current_user ? User.current_user.email : "system"
      issue_data = {"name" => "New haproxy request for #{user}", "description" => "Haproxy config: #{body}", "priority" => 3}
      Issue.new_support_issue(issue_data)
    end
    response
  end

  def edit_service_routes(object, data)
    body = generate_body(object, data)
    conn = connection
    request = put_request("/api/1/routes/#{data["route_id"]}", body)
    response = conn.request(request)
    issue_data = {"name" => "New haproxy request for #{User.current_user.email}", "description" => "Haproxy config: #{body}", "priority" => 3}
    Issue.new_support_issue(issue_data)
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

    if response.kind_of?(Net::HTTPSuccess)
      user = User.current_user ? User.current_user.email : "system"
      issue_data = {"name" => "Haproxy delete request for #{user}", "description" => "Haproxy config: #{haproxy_config}", "priority" => 3}
      Issue.new_support_issue(issue_data)
    end

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
    _log.info("DBG send body #{body.to_json}")
    request.body = body.to_json
    request
  end

  def put_request(url, body)
    request = Net::HTTP::Put.new(url)
    request.add_field("X_HAPROXYAPI_KEY", api_key)
    _log.info("DBG send body #{body.to_json}")
    request.body = body.to_json
    request
  end

  def delete_request(url)
    request = Net::HTTP::Delete.new(url)
    request.add_field("X_HAPROXYAPI_KEY", api_key)
    request
  end

  def generate_body(object, data)
    data = data.symbolize_keys
    body = {
      "name"           => data[:name],
      "host"           => data[:dns],
      "proto"          => data[:externalProtocol].downcase,
      "service_id"     => object.id,
      "approve_status" => "approved",
      "project"        => data[:project],
      "purpose"        => data[:purpose],
      "backend"        => {
        "balance" => "roundrobin",
        "proto"   => data[:internalProtocol].downcase,
        "servers" => [],
      },
    }

    @region = object.region_number

    data[:vms].each do |vm|
      vm = vm.symbolize_keys
      raise "Wrong or private IP address #{vm[:host]}" unless ip_allowed(vm[:host])
      server = {"name" => vm[:id], "host" => vm[:host], "port" => data[:port]}
      body["backend"]["servers"].push(server)
    end
    body
  end

  def public_subnets
    @public_subnets ||= find_public_subnets
  end

  def request_subnets
    foreman_config = YAML.load_file('config/foreman_config.yml')[@region]

    uri = URI.parse(foreman_config[:foreman_url])

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Get.new('/api/subnets')
    req.basic_auth(foreman_config[:user], foreman_config[:password])

    response = http.request(req)
    JSON.parse(response.body)["results"]
  end

  def find_public_subnets
    request_subnets.map { |s| IPAddr.new("#{s["network"]}/#{s["mask"]}") if s["name"].include?("pvl") }.compact
  end

  def ip_allowed(ip)
    public_subnets.find { |s| s.include?(ip) }
  end
end
