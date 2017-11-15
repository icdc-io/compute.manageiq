class MiqGroupQuota < Quota

  belongs_to :miq_group

  validates :name,
            :inclusion  => {:in => NAMES},
            :uniqueness => {:scope => :miq_group_id, :message => "should be unique per miq_group"}

  def self.format_quota_value(field, field_value, quota_name)
    if field == "miq_group_quotas.name" 
      MiqGroupQuota.quota_description(quota_name.to_sym)
    else
      row = QUOTA_BASE[quota_name.to_sym]
      OpsHelper::TextualSummary.convert_to_format(row[:format], row[:text_modifier], field_value)
    end
  end


  def allocated
    miq_group.users.includes(:user_quotas).map do |c|
      cq = c.user_quotas.send(name).take
      cq.value if cq
    end.compact.sum
  end

  def available
    (value - used - allocated)
  end
 
  def used
    method = "#{name.split("_").first}_used"
    @used ||= send(method)
  end

  def used_by_users
    miq_group.users.includes(:user_quotas).map do |c|
      cq = c.used_quotas
      cq.value if cq
    end.compact.sum
  end

  def svm_used
   [ cpu_used, (mem_used.to_f / 1.gigabyte).ceil ].max
  end

  def cpu_used
    miq_group.allocated_vcpu
  end

  def mem_used
    miq_group.allocated_memory
  end

  def storage_used
    miq_group.allocated_storage
  end

  def vms_used
    miq_group.active_vms.count
  end

  def templates_used
    miq_group.miq_templates.count
  end

  def hours_used
    miq_group.svmh_used
  end

  def validate_quota
    validate_quota_base(miq_group.current_tenant)
  end
end  
