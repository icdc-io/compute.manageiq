module IcdcUserMixin
  extend ActiveSupport::Concern

  # rubocop:disable Naming/AccessorMethodName, Lint/MissingCopEnableDirective

  included do
    virtual_attribute :ssh_keys, :string
    virtual_column :get_user_subnets, :type => :string
    virtual_column :get_user_available_subnets, :type => :string
  end

  def get_user_subnets
    networks = tags(:networks).to_a # fix #3447
    networks.push(*current_group.tags(:networks))
    networks.push(*current_group.tenant.tags(:networks))
    current_group.tenant.ancestry.split('/').each do |tenant_id|
      networks.push(*Tenant.find_by(:id => tenant_id).tags(:networks))
    end
    networks = networks.uniq
    nets = []
    networks.each do |tag|
      tag_info = {}
      next unless /\/managed\/networks\// =~ tag.name

      tag_info["subnet"] = tag.categorization["name"]
      tag_info["description"] = tag.categorization["description"]
      unless tag_info["description"].include?("All IP consumed")
        nets.push(tag_info)
      end
    end
    nets
  end

  def get_user_available_subnets
    all_user_networks = get_user_subnets
    return nil if all_user_networks.empty?

    available_networks = Icdc::Foreman::Client.new(miq_region.region).free_ips(all_user_networks.collect { |x| x["subnet"] }).reject { |entry| entry[:ip].nil? }.map { |entry| entry[:subnet] }
    all_user_networks.select { |entry| available_networks.include?(entry["subnet"]) }
  end

  def ssh_keys
    {:ssh_keys => available_keys}
  end

  def available_keys
    result = []
    GenericObject.all.select { |go| go.generic_object_definition_name == "SshKey" }.select { |go| go.user.first }.select { |go| go.user.first.email == email }.map do |go|
      template = { :name => go.name, :key => go["properties"]["key"], :id => go.id }
      result.push(template)
    end
    result
  end
end
