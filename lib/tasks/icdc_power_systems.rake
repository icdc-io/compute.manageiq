namespace :icdc_power_systems do
  desc "Create Nim Server, run scaning, create images"
  task :prepare_nim => :environment do
    nim_server = Vm.find_by(:name => "AIX_NIM")
    NimServer.create(:name => nim_server.name, :uri => nim_server.ext_management_system.guid, :access_url => nim_server.ipaddresses.first)
  end

  desc "Discovery images for provisioning from NimServers"
  task :prepare_images => :environment do
    NimServer.all.each{|nim| nim.sync_pxe_images}
    PxeImage.all.each{|image| image.update!(:pxe_image_type_id => PxeImageType.find_by(:name => "AIX").id)}
  end

  desc "Create AIX image_type"
  task :prepare_image_type => :environment do
    PxeImageType.create(:name => "AIX", :provision_type => "")
  end

  desc "Create Blank Template"
  task :prepare_blank_template => :environment do
    vm = ManageIQ::Providers::Power::InfraManager::Vm.new(:name => "Blank Template SystemP",
                                                          :template => true, 
                                                          :vendor => "power_systems", 
                                                          :location => "power_systems", 
                                                          :ext_management_system => ExtManagementSystem.select{|ems| ems.type.include?("Providers::Power")}.first
                                                          )
    hw = Hardware.create(:memory_mb => "1024",
                         :size_on_disk => "30", 
                         :cpu_cores_per_socket => 1,
                         :cpu_total_cores => 1,
                         :guest_os_full_name => "AIX"
                        )
    vm.hardware = hw
    vm.save!
  end

  desc "Automate deployment System P in Compute"
  task :deploy => :environment do
    Rake::Task['icdc_power_systems:prepare_nim'].invoke 
    Rake::Task['icdc_power_systems:prepare_image_type'].invoke
    Rake::Task['icdc_power_systems:prepare_images'].invoke
    Rake::Task['icdc_power_systems:prepare_blank_template'].invoke
  end
end
