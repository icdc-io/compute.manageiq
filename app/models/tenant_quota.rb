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
    tenants_allocated = tenant.children.includes(:tenant_quotas).map do |c|
      cq = c.tenant_quotas.send(name).take
      cq.value if cq
    end.compact.sum
    return tenants_allocated + allocated_by_groups
  end

  def allocated_by_groups
    tenant.miq_groups.includes(:miq_group_quotas).map do |c|
      next unless c.miq_group_quotas.respond_to?(name)
      cq = c.miq_group_quotas.send(name).take
      cq.value if cq
    end.compact.sum
  end

  def available
    value - used - allocated
  end

  def used
    method = "#{name.split("_").first}_used"
    @used ||= send(method)
  end

  def used_by_groups
    tenant.miq_groups.includes(:miq_group_quotas).map do |c|
      cq = c.miq_group_quotas.available_quotas
      cq.value if cq
    end.compact.sum
  end

  def svm_used
    [ cpu_used, (mem_used.to_f / 1.gigabyte).ceil ].max
  end

  def cpu_used
    res = 0
    for ten in tenant.subtree do
      next if !ten.tenant_quotas.empty? && ten != tenant
      for group in ten.miq_groups
        res += group.allocated_vcpu if group.quota_holder == tenant
      end
    end
    res  
  end

  def mem_used
    res = 0
    for ten in tenant.subtree do
      next if !ten.tenant_quotas.empty? && ten != tenant
      for group in ten.miq_groups
        res += group.allocated_memory if group.quota_holder == tenant
      end
    end
    res
  end

  def storage_used
    res = 0
    for ten in tenant.subtree do
      next if !ten.tenant_quotas.empty? && ten != tenant
      for group in ten.miq_groups
        res += group.allocated_storage if group.quota_holder == tenant
      end
    end
    res
  end

  def vms_used
    tenant.active_vms.count
  end

  def hours_used
    res = 0
    for ten in tenant.subtree do
      next if !ten.tenant_quotas.empty? && ten != tenant
      for group in ten.miq_groups
        res += group.svmh_used if group.quota_holder == tenant
      end
    end
    res
  end

  def templates_used
    tenant.miq_templates.count
  end

  # remove all quotas that are not listed in the keys to keep
  # e.g.: tenant.tenant_quotas.destroy_missing_quotas(include_keys)
  # NOTE: these are already local, no need to hit db to find them
  def self.destroy_missing(keep)
    keep = keep.map(&:to_s)
    deletes = all.select { |tq| !keep.include?(tq.name) }
    delete(deletes)
  end

  def quota_hash
    self.class.quota_definitions[name.to_sym].merge(:unit => unit, :value => value, :warn_value => warn_value, :format => format) # attributes
  end

  def default_unit
    self.class.quota_definitions.fetch_path(name.to_sym, :unit).to_s
  end

  def validate_quota
    return if tenant.root? || tenant.parent.root?
    validate_quota_base(tenant.parent)
  end
end
