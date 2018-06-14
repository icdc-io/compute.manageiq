class TenantQuota < Quota

  belongs_to :tenant

  validates :name,
            :inclusion  => {:in => NAMES},
            :uniqueness => {:scope => :tenant_id, :message => "should be unique per tenant"}


  def self.format_quota_value(field, field_value, tenant_quota_name)
    if field == "tenant_quotas.name"
      TenantQuota.quota_description(tenant_quota_name.to_sym)
    else
      row = QUOTA_BASE[tenant_quota_name.to_sym]
      OpsHelper::TextualSummary.convert_to_format(row[:format], row[:text_modifier], field_value)
    end
  end

  def allocated
    tenant.children.includes(:tenant_quotas).map do |c|
      cq = c.tenant_quotas.send(name).take
      cq.value if cq
    end.compact.sum
  end

  def available
    value - used - allocated
  end

  def used
    @used ||= tenant.resource_used(name.split("_").first)
  end

  def validate_quota
    return if tenant.root? || tenant.parent.root?
    validate_quota_base(tenant.parent)
  end

end

