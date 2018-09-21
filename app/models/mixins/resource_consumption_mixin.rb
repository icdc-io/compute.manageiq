module ResourceConsumptionMixin
  extend ActiveSupport::Concern

  def resource_used(resource_name)
    send("#{resource_name}_used")
  end

  def svm_used
    [cpu_used, (mem_used.to_f / 1.gigabyte).ceil].max
  end

  def cpu_used
    allocated_vcpu
  end

  def mem_used
    allocated_memory.to_f / 1.gigabyte
  end

  def storage_used
    allocated_storage / 1.gigabyte
  end

  def hours_used
    svmh_used
  end

  def vms_used
    active_vms.count
  end

  def templates_used
    miq_templates.count
  end

end
