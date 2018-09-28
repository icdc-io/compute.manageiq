module UserQuotableMixin
  extend ActiveSupport::Concern
  include QuotableMixin

  included do
    has_many :user_quotas

    belongs_to :quota_holder, :class_name => "Tenant"
    after_commit :update_quota_holder_associations
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

  def personal_quotas
    {
      type:                 "user",
      description:          "Available Resources",
      name:                 self.userid,
      title:                self.userid,
      edit_action:          "order",
      service_template_id:  15,
      locations:            user_resources_by_locations(true)
    }
  end

  def update_quota_holder_associations
    #Fix: https://support.icdc.io/issues/5536
    #Special case here as we use this method when creating new users from MAIN server, but in SLAVE database
    Tenant.in_region(region_id).roots.first.update_quota_holder_associations
  end

  def user_resources_by_locations(personal = false)
    @locations = []
    for slave_region in MiqRegion.slave_regions
      user_in_region = User.find_in_region({ userid: self.userid }, slave_region.region)

      next unless user_in_region

      location_resources = {
          id:         user_in_region.id,
          name:       slave_region.description,
          full_name:  slave_region.full_name,
      }

      if personal
        account = user_in_region.quota_holder
        location_resources[:quota], location_resources[:account] = user_in_region.combined_quotas_personal
      else
        location_resources[:quota] = user_in_region.combined_quotas[0]
      end
      @locations.push(location_resources)
    end
    @locations
  end

  def monthly_chargeback(months)
    chargeback_for = [DateTime.now.month]
    if months > 1
      for number_of_month in 1..months - 1
        chargeback_for.push(number_of_month.month.ago.month)
      end
    end
    services = services
    if services.empty?
      return chargeback_for.map { |month| {"start_date": month, "cost": 0} }
    end
    costs = services.flat_map { |service| service.total_costs_monthly(chargeback_for) }
    group_bydate_and_sum(costs)
  end

  def combined_quotas_personal
    quota = combined_quotas.deep_dup
    used = used_quotas
    account = quota_holder
    if account
      use_account = true
      account_quota = account.available_quotas
      account_quota.each do |key, value|
        resource_name = key.to_s.split("_").first
        next unless value[:value]
        if quota[key][:available] && quota[key][:available] < value[:value]
          use_account = false
        else
          quota[key][:available] = value[:value]
          quota[key][:used] ||= resource_used(resource_name) 
        end
        quota[key][:value] = quota[key][:available] + quota[key][:used]
        quota[key][:name] = resource_name 
      end
    end
    return [quota] unless use_account 
    return quota, account.description
  end

  def combined_quotas
    user_quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash
      h[q.name.to_sym][:used]        = q.used
      h[q.name.to_sym][:available]   = q.available
    end.reverse_merge(Quota.quota_definitions)
  end

end
