module ServiceChargebackMixin
  extend ActiveSupport::Concern

  def get_services_in_regions
    region, id = self.split_id
    services_data = []
    if MiqRegion.default? region
      for reg in MiqRegion.slaves_only
        node_in_region = self.class.find_by_id(self.class.id_in_region(id, reg.region))
        next unless node_in_region
        services_in_region = yield(node_in_region)
        serv_data = services_in_region.map do |s|
          data = s.as_json
          data["evm_owner"] = {}
          data["evm_owner"] = s.evm_owner.as_json if s.evm_owner
          data["tenant"] = {}
          data["tenant"]["name"] = s.tenant.name if s.tenant
          data["total_costs_bydate"] = s.total_costs_bydate
          data["location"] = reg.as_json
          data["location"]["full_name"] = reg.full_name
          data
        end
        services_data.push(*serv_data)
      end
    end
    services_data
  end

end
