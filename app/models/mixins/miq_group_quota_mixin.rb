module MiqGroupQuotaMixin
  extend ActiveSupport::Concern
  include QuotableMixin

  included do
    has_many :miq_group_quotas
  end

  def get_quotas
    get_quotas_base(miq_group_quotas)
  end

  def set_quotas(quotas)
    set_quotas_base(miq_group_quotas, quotas)
  end

  def used_quotas
    used_quotas_base(miq_group_quotas)
  end

  def allocated_quotas
    allocated_quotas_base(miq_group_quotas)
  end

  def available_quotas
    available_quotas_base(miq_group_quotas)
  end

  def tenant_group?
    self.group_type == 'tenant'
  end

  def quota_holder
    return self unless miq_group_quotas.empty?
    tenant = current_tenant
    return tenant.quota_holder
  end

  def build_quota_tree(root=false)
    region, id = MiqGroup.split_id(self.id)
    if MiqRegion.default? region
      root_group_node = {
          "type" => "group",
          "id" => self.id,
          "name" => self.name,
          "service_template_id" => Quota.service_template.id,
          "children" => group_users_nodes,
          "locations" => []
      }
        set_edit_action_to_children(root_group_node)
      if root
        root_group_node["edit_action"] = "order"
      end
      manage_locations(root_group_node)
      root_group_node
    end
  end

  def group_users_nodes
    users_nodes = []
    for user in self.users
      users_nodes.push({
            "name" => user.userid,
            "id" => user.id,
            "type" => "user",
            "description" => "#{name} users",
            "locations" => user.user_resources_by_locations
      })
    end
    users_nodes
  end

   def combined_quotas
     combined_quotas_base(miq_group_quotas)
  end

end
