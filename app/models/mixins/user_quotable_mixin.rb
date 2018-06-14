module UserQuotableMixin
  extend ActiveSupport::Concern
  include QuotableMixin

  included do
    has_many :user_quotas

    belongs_to :quota_holder, :class_name => "Tenant"
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
    available_quotas_base(user_quotas)
  end

  def personal_quotas
    {
      type:                 "user",
      description:          "Available Resources",
      name:                 self.userid,
      title:                self.userid,
      edit_action:          "order",
      service_template_id:  Quota.service_template.id,
      locations:            user_resources_by_locations(true)
    }
  end

  def user_resources_by_locations(personal = false)
    locations = []

    for slave_region in MiqRegion.slave_regions
      user_in_region = User.in_region(slave_region.region).where(userid: self.userid).first
      next unless user_in_region
      $log.info("QUOTA next #{user_in_region}")
      if personal
        account = user_in_region.quota_holder
        account_name = account.name if account
      end
      $log.info("QUOTA personal #{account}")
      next if personal && !account
      location_resources = {
          id:         user_in_region.id,
          name:       slave_region.description,
          full_name:  slave_region.full_name,
          chargeback: user_in_region.services_chargebacks,
      }
      if personal
        if account == user_in_region
          location_resources[:quota] = account.combined_quotas_personal
        else
          location_resources[:quota] = account.combined_quotas
          location_resources[:account] = account.description
        end
      else
        location_resources[:quota] = user_in_region.combined_quotas
      end
      locations.push(location_resources)
      $log.info("QUOTA location #{location_resources}")
    end
    locations
  end

  def combined_quotas_personal
    quota = combined_quotas.deep_dup
    account = current_group.tenant.quota_holder
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
    user_quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash
      h[q.name.to_sym][:available]   = q.available
      h[q.name.to_sym][:used]        = q.used
    end.reverse_merge(Quota.quota_definitions)
  end

end

