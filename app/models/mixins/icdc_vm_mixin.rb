module IcdcVmMixin
  def add_additional_nic(lan_name)
    vnic_profile_id = find_vnic_profile_id(lan_name)
    nic_name = generate_nic_name
    add_nic(nic_name, vnic_profile_id) if vnic_profile_id
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
end
