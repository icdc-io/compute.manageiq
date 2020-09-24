module IcdcUserMixin
  extend ActiveSupport::Concern

  # rubocop:disable Naming/AccessorMethodName, Lint/MissingCopEnableDirective

  included do
    virtual_attribute :ssh_keys, :string
    virtual_column :subnets, :string
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

 
  def subnets
    subnet_hash = {}
    ovn_subnets = CloudSubnet.all.select{ |subnet| subnet.name.match?("#{MiqRegion.my_region.description.downcase}_#{current_tenant.name.downcase}_") }
                                 .collect(&:name).map { |subnet_name| subnet_hash.merge!("#{subnet_name} (#{subnet_name})" => subnet_name) }
    foreman_tenant = Icdc::Foreman::Organization.new(:region => MiqRegion.my_region.region, :tenant_name => current_tenant.name)
    foreman_tenant.subnets.map { |subnet| subnet_hash.merge!("#{subnet.name} (#{subnet.name})" => subnet.description) } if foreman_tenant.ready?
    subnet_hash
  end
end
