namespace :icdc do


namespace :support do
  desc "Remove incorrect backups records, that has no template or vms"
  task :remove_backups_no_template_or_vms => :environment do
    s_outdated = Service.all.select { |s| s.outdated_backups.present? }

    s_outdated.each do |service|
      backups_to_delete = service.backups.select do |backup|
        vms = backup[:serialized_value]["vms"]
        templates_ids = vms.map{ |vm_id, vm| vm["t_id"] }
        has_nonexistent_ids = templates_ids.any? { |t_id| MiqTemplate.find_by(id: t_id).nil? }
        has_nonexistent_ids || vms.empty?
      end

      backups_to_delete.each{ |backup| backup.destroy }
    end

  end

end


namespace :dev do
  desc "Delete all miq_schedules after deployment of DEV environment"
  task :remove_schedules => :environment do
    #MiqSchedule.all.delete_all
    MiqSchedule.where('description NOT LIKE ?', 'rss_%').where('description NOT LIKE ?', 'report_%').where('description NOT LIKE ?', 'chart_%').where('description NOT LIKE ?', 'tenant_%').delete_all
  end


  desc "Setup separate credentials for DEV environment"
  task :redhat_creds, [:env] => :environment do |_, args|
    provider = ManageIQ::Providers::Redhat::InfraManager.first.authentications.where(authtype: "default").first
    if args.nil? or args[:env].nil?
      abort("Provide env name. For example: rake #{_}[dev3]")
    end
    env = args[:env].to_sym
    location = MiqRegion.my_region.description.downcase.to_sym
    creds = {
      idc: {
        dev1: {userid: "dcdev1@IBA", password: "U7X8Y@D7"},
        dev2: {userid: "dcdev2@IBA", password: "ob$2jAO7"},
        dev3: {userid: "dcdev3@IBA", password: "aTt9MsjX"},
        dev4: {userid: "dcdev4@IBA", password: "x3-uGEEf"}
      },
      nb5: {
      },
    }
    cred = creds.try(location).try(env)
    if cred.nil?
      abort("Credentials not specified for location[#{location}] and environment[#{env}]")
    end
    provider.userid = cred[:userid]
    provider.password = cred[:password]
    provider.save
  end
end


end
