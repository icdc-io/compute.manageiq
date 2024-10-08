module IcdcVmMixin
  def add_additional_nic(lan_name)
    vnic_profile_id = find_vnic_profile_id(lan_name)
    nic_name = generate_nic_name
    add_nic(nic_name, vnic_profile_id) if vnic_profile_id
  end

  def enable_nested_virtualization
    raise RuntimeError.new('Nested virtualization already enabled') if nested_virtualization_enabled?
    cpu_type = ems_cluster.hosts.first.hardware.cpu_type.downcase
    cpuflags = '+vmx'
    cpuflags = '+svm' if cpu_type.include?('amd')
    add_custom_property({name: 'cpuflags', value: cpuflags})
    add_affinity_label('nested_virtualization')
    refresh_ems
  end

  def disable_nested_virtualization
    railse RuntimeError.new('Nested virtualization already disabled') unless nested_virtualization_enabled?
    
    delete_custom_property('cpuflags')
    delete_affinity_label('nested_virtualization')
    refresh_ems
  end

  private

  def find_vnic_profile_id(lan_name)
    Lan.find_by(:name => lan_name).uid_ems
  end

  def generate_nic_name
    nic_range = []
    nic_in_use = nics.collect(&:name)
    (1..nics.count+1).each {|i| nic_range.append("nic#{i}")}
    available_nics = nic_range - nic_in_use
    available_nics[0]
  end

  def nested_virtualization_enabled?
    custom_attributes.collect(&:name).include?('cpuflags')
  end
end
