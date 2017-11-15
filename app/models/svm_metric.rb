class SvmMetric < ApplicationRecord
  belongs_to :vm
  belongs_to :user
  belongs_to :miq_group
  belongs_to :tenant

  def self.collect_svm
    _log.info("[DBG] Starting collect_svm")
    self.store
    SvmMetricRollup.store
  end

private

  def self.store
    _log.info("Starting collection of hourly SVM per user usage")
    Vm.find_each do |vm|
      d = {cpu:0, mem:0, nic:0}
      if vm.active? #only real machines
        if vm.state.eql?('on')
          d[:cpu] = vm.cpu_total_cores
          d[:mem] = vm.ram_size_in_bytes_by_state / 1.gigabyte
        end
        d[:nic] = vm.lans.count #NICs caluclated whatever power state as it reservs MAC/IP
      end
      d[:svm] = d.values.max.ceil #calculate SVM
      $api_log.info("[DBG] calc vm:#{vm.name}; active:#{vm.active?}; owner:#{vm_owner_id(vm)}; group:#{vm_group_id(vm)}; tenant:#{vm_tenant_id(vm)}; state:#{vm.state}; svm:#{d[:svm]}; cpu:#{d[:cpu]}; mem:#{d[:mem]}; nic:#{d[:nic]}")
      m = SvmMetric.new
      m.vm_id = vm.id
      m.user_id = vm_owner_id(vm)
      m.miq_group_id = vm_group_id(vm)
      m.tenant_id = vm_tenant_id(vm)
      m.state = vm.state
      m.cpu = d[:cpu]
      m.mem = d[:mem]
      m.nic = d[:nic]
      m.svm = d[:svm]
      m.ts = Time.new
      begin
        m.save
      rescue => err
       _log.error("Failed to store SvmMetric for VM[#{vm.name}]: #{err}")
      end
      SvmMetric.where('ts < ?', 30.days.ago).each do |m|
        m.destroy
      end
    end
    _log.info("Passed through all VM")
  end

  def self.vm_owner_id(vm)
    id = vm.evm_owner_id
    if id.nil?
      svc = vm.direct_service
      id = svc.evm_owner_id unless svc.nil?
    end
    id
  end


  def self.vm_group_id(vm)
    id = vm.miq_group_id
    if id.nil?
      svc = vm.direct_service
      id = svc.miq_group_id unless svc.nil?
    end
    id
  end

  def self.vm_tenant_id(vm)
    id = vm.tenant_id
    if id.nil?
      svc = vm.direct_service
      id = svc.tenant_id unless svc.nil?
    end
    id
  end

end

