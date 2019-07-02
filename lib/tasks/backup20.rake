namespace :backup20 do
  desc "Create Backup2.0 from Old Backup"
  task :update_backup, [:backup_id] => :environment do | _, args|
    backup = CustomAttribute.find(args[:backup_id])
    name = template_id = vm_id  =""
    backup.serialized_value["vms"].each_value{|x| name = x["name"]}
    backup.serialized_value["vms"].each_value{|x| template_id = x["t_id"]}
    created_at = backup.serialized_value["start_date"]
    backup.serialized_value["vms"].each_key{|x| vm_id = x}
    vm = VmOrTemplate.find(vm_id)
    template = VmOrTemplate.find(template_id)
    # GET VM CONFIGURATION
    configuration = {}
    configuration[:disks] = {}
    configuration[:nics] = {}
    configuration[:vm_name] = vm.name
    vm.disks.each do |disk|
      configuration[:disks][disk.device_name] = {}
      configuration[:disks][disk.device_name][:storage_type] = Storage.find(disk.storage_id).tags.select { |s| s if /storage_type/ =~ s.name }.first.name.split('/').last
    end
    vm.hardware.nics.each do |nic|
      configuration[:nics][nic.device_name] = {}
      configuration[:nics][nic.device_name][:id] = nic.uid_ems
      configuration[:nics][nic.device_name][:mac] = nic.address
    end

    # Create GenericObject Backup
    new_backup = GenericObjectDefinition.where(:name => "Backup")
      .first
        .create_object(
          :name          => "bkp_#{vm.id}_#{Time.now.strftime('%Y%m%d-%H%M')}", # rubocop:disable Rails/TimeZone 
          :error         => false,
          :terminated    => false,
          :template_id   => template_id,
          :created_at    => created_at,
          :description   => "#{name}_old_backup",
          :status        => "ready",
          :configuration => configuration)   
    new_backup.template = [template]
    new_backup.service = [vm.service]
    new_backup.save!
  end
end
