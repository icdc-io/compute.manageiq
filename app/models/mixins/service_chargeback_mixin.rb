module ServiceChargebackMixin
  extend ActiveSupport::Concern

  def services_chargeback(user = nil)
    region, id = self.split_id
    services_data = []
    search_attr = self.class.search_attribute

        node_in_region = self
        
        if user.present?
          services_in_region = node_in_region.services.includes(:evm_owner).select{ |service| service.evm_owner.userid == user.userid }
        else
          services_in_region = node_in_region.subtree.inject([]) { |services, desc| services + desc.services }
        end
        
        serv_data = services_in_region.map do |s|
          data = {}
          data[:id] = s.id
          data[:name] = s.name
          data[:evm_owner] = {}
          data[:evm_owner][:name] = s.evm_owner.name if s.evm_owner
          data[:tenant] = {}
          data[:tenant][:description] = s.tenant.description if s.tenant
          data[:total_costs_bydate] = s.total_costs_bydate('two_months')
          data[:location] = region.as_json
          data
        end
        services_data.push(*serv_data)
        services_data
  end
end
