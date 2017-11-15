class UserQuota < Quota

  belongs_to :user


  validates :name,
            :inclusion  => {:in => NAMES},
            :uniqueness => {:scope => :user_id, :message => "should be unique per user"}


  def self.format_quota_value(field, field_value, quota_name)
    if field == "user_quotas.name"
      UserQuota.quota_description(quota_name.to_sym)
    else
      row = QUOTA_BASE[quota_name.to_sym]
      OpsHelper::TextualSummary.convert_to_format(row[:format], row[:text_modifier], field_value)
    end
  end

  def allocated
    value
  end

  def available
    (value - used)
  end

  def used
    method = "#{name.split("_").first}_used"
    @used ||= send(method)
  end

  def svm_used
   [ cpu_used, (mem_used.to_f / 1.gigabyte).ceil ].max
  end

  def cpu_used
    user.allocated_vcpu
  end

  def mem_used
    user.allocated_memory
  end

  def storage_used
    user.allocated_storage
  end

  def vms_used
    user.active_vms.count
  end
 
  def hours_used
    user.svmh_used
  end

  def templates_used# remove all quotas that are not listed in the keys to keep
    user.miq_templates.count
  end

  def validate_quota
    #validate_quota_base(user.quota_holder)
  end

end  
