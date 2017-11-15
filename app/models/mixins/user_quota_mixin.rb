module UserQuotaMixin
  extend ActiveSupport::Concern
  include QuotableMixin

  included do
    has_many :user_quotas
  end

  def get_quotas
    get_quotas_base(user_quotas)
  end

  def set_quotas(quotas)
    set_quotas_base(user_quotas, quotas)
  end

  def used_quotas
    used_quotas_base(user_quotas)
  end

  def allocated_quotas
    allocated_quotas_base(user_quotas)
  end

  def available_quotas
    #_log.info("DBG user available quota #{available_quotas_base(user_quotas).inspect}")
    #_log.info("DBG account available quota #{current_group.quota_holder.available_quotas.inspect}")
    available_quotas_base(user_quotas)
    #min(available_quotas_base(user_quotas), current_group.quota_holder.available_quotas)
  end

  def quota_holder
    #_log.info("DBG quota holder")
    return self unless user_quotas.empty?
    miq_group = self.current_group
    return miq_group unless miq_group.miq_group_quotas.empty?
    tenant = miq_group.current_tenant
    return tenant.quota_holder 
  end

  def personal_quotas
    node = {
        "type" => "user",
        "description" => "Available Resources",
        "name" => self.userid,
        "edit_action" => "order",
        "service_template_id" => Quota.service_template.id,
        "locations" => user_resources_by_locations(true)
    }
    node
  end

  def user_resources_by_locations(personal = false)
    region, id = User.split_id(self.id)
    locations = []
    if MiqRegion.default? region
      for slave_region in MiqRegion.all
        next if slave_region.default?
        user_in_region = User.find_by_id(User.id_in_region(id, slave_region.region))
        next unless user_in_region
        if personal
          account = user_in_region.quota_holder
          account_name = account.name if account
        end 
        next if personal && !account
        location_resources = {
            "id" => user_in_region.id,
            "name" => slave_region.description,
            "full_name" => slave_region.full_name,
            "chargeback" => user_in_region.services_chargebacks,
        }
        if personal
          if account == user_in_region
            location_resources["quota"] = account.combined_quotas_personal
          else
            location_resources["quota"] = account.combined_quotas
            location_resources["node_name"] = account_name
          end
        else
          location_resources["quota"] = user_in_region.combined_quotas
        end
        locations.push(location_resources)
      end
    end
    locations
  end

  def combined_quotas_personal
    quota = combined_quotas_base(user_quotas).deep_dup
    account = current_group.quota_holder    
    if account
      account_quota = account.available_quotas
      account_quota.each do |key, value|
        next unless value[:value]
        if quota[key][:available]
          quota[key][:available] = [quota[key][:available], value[:value]].min
        else
          quota[key][:available] =  value[:value]
        end
        quota[key][:value] = quota[key][:available] + quota[key][:used] if quota[key][:used]
      end
    end
    quota
  end

  def combined_quotas
    quota = combined_quotas_base(user_quotas)
  end

end
