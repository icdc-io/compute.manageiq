module IcdcServiceMixin
  extend ActiveSupport::Concern

  included do
    extend InterRegionApiMethodRelay

    virtual_column :domains,           :type => :string
    virtual_column :shared_users,      :type => :string
    virtual_column :miq_request_state, :type => :string
    virtual_column :networks,          :type => :string
    virtual_column :available_networks, :type => :string
    virtual_column :subnets,           :type => :string # Legacy

    api_relay_method :share do |options|
      options
    end

    api_relay_method :unshare do |options|
      options
    end

    api_relay_method :invoke_custom_button do |options|
      options
    end
  end

  def share(data)
    project_tag = find_project_tag || create_porject_tag

    userids = data['userids']

    Classification.classify(self, 'project', project_tag)

    userids.each do |userid|
      user = User.find_by(:userid => userid)
      Classification.classify(user, 'project', project_tag)

      # TODO: email user
    end

    vms.each { |vm| Classification.classify(vm, 'project', project_tag) }
  end

  def unshare(data)
    userid = data['userid']
    user = User.find_by(:userid => userid)
    project_tag = find_project_tag
    Classification.unclassify(user, 'project', project_tag)
  end

  def shared_users
    project_tag = find_project_tag

    project_tag ? User.find_tagged_with(:any => project_tag, :ns => '/managed/project') : []
  end

  def domains
    # rubocop:disable Rails/DynamicFindBy, it's static method in Classification class
    Classification.where(:parent_id => Classification.lookup_by_name('domain', region_number)&.id).map(&:description)
    # rubocop:enable Rails/DynamicFindBy
  end

  def invoke_custom_button(data)
    action = data['task']
    custom_button = resource_custom_action_button(action)
    if custom_button.resource_action.dialog_id
      return invoke_custom_action_with_dialog(type, self, action, data, custom_button)
    end

    custom_button.invoke(self)
  end

  def miq_request_state
    miq_request.nil? ? 'finished' : miq_request.request_state
  end

  def networks
    networks = Icdc::Network.authorized_networks(self).compact
    # FIX: currently we allow only one authorized subnet (IPv4 or IPv6) on L2 logical network
    auth_net_lookup = networks.group_by(&:name)
    # Merge information about guest networks into authorized networks
    Icdc::Network.guest_networks(self).each do |gnet|
      auth_net = auth_net_lookup[gnet.name]&.first
      if auth_net
        auth_alloc_lookup = auth_net.allocations.group_by(&:ip)
        gnet.allocations.each do |galloc|
          unless auth_alloc_lookup[galloc.ip]
            auth_net.allocations << galloc
          end
        end
      else # push whole network
        networks << gnet
      end
    end
    # Sort IP Allocations by Service or VM, and then by IP type: IPv4, IPv6
    networks.each { |net| net.allocations = net.allocations.sort_by{ |a| [a.service_id || a.vm_id || 0, a.ip] } }
    networks
  end

  def available_networks
    account = evm_owner.current_tenant.project? && evm_owner.current_tenant.parent || evm_owner.current_tenant
    # OVN Networks
    nets = CloudSubnet.all.select{ |subnet| 
      subnet.name.match?("#{MiqRegion.my_region.description.downcase}_#{account.name.downcase}_")
    }.map{ |subnet|
      { :subnet => subnet.name, :description => (subnet.name.split("_")[2..-1]&.join("_") || subnet.name).humanize() }
    }
    # Foreman Networks
    foreman_tenant = Icdc::Foreman::Organization.new(:region => MiqRegion.my_region.region, :tenant_name => account.name)
    nets += foreman_tenant.subnets.map{ |subnet| {:subnet => subnet.name, :description => subnet.description} } if foreman_tenant.ready?
    nets
  end
  alias_method :subnets, :available_networks

  def add_haproxy_routes(data)
    proxy_server = HaproxyCluster.get_proxy_server(self)
    raise RuntimeError, "Haproxy cluster doesn't found" unless proxy_server
    response = proxy_server.add_service_routes(self, data)
    return {:host => JSON.parse(response.body).dig("host"), :port => JSON.parse(response.body).dig("port")}
  end

  def remove_haproxy_routes
    proxy_service = HaproxyCluster.get_proxy_server(self)
    raise RuntimeError, "Haproxy cluster doesn't found" unless proxy_server
    routes_ids = proxy_server.get_service_routes(object).collect{ |route| route["id"] }
    routes_ids.each { |route_id| proxy_server.delete_service_routes(self, {:route_id => route_id}) }
  end

  private

  def invoke_custom_action_with_dialog(_type, resource, _action, data, custom_button)
    submit_custom_action_dialog(resource, custom_button, data)
  end

  def submit_custom_action_dialog(resource, custom_button, data)
    wf = ResourceActionWorkflow.new({}, User.current_user, custom_button.resource_action, :target => resource)
    data.each { |key, value| wf.set_value(key, value) } if data.present?
    wf_result = wf.submit_request
    raise StandardError, Array(wf_result[:errors]).join(", ") if wf_result[:errors].present?

    wf_result
  end

  def resource_custom_action_button(action)
    custom_action_buttons.find { |b| b.name.downcase == action.downcase }
  end

  def find_project_tag
    tags.where("name LIKE?", "%/project/%").first&.classification&.name
  end

  def create_porject_tag
    tag = (0...3).map { ('a'..'z').to_a[rand(26)] }.join.downcase + evm_owner_id.to_s
    Classification.find_by_name('project').add_entry(:name => tag, :description => tag).name # rubocop:disable Rails/DynamicFindBy, it's static method in Classification class
  end
end
