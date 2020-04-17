namespace :icdc do
  desc 'assigning backups to owner'
  task :assign_backup => :environment do
    srv = Service.all.select{|x| x.backups.present?}
    for service in srv
      for x in service.backups
          name = x.value.split('vms')[1].split('=>')[4].split('"')[1]
          if !name.nil?
	  templ = MiqTemplate.find_by_name(name)
          if !templ.nil?
          templ.evm_owner_id = service.evm_owner_id unless service.evm_owner_id.nil?
          templ.miq_group_id = service.miq_group_id unless service.miq_group_id.nil?
          templ.tenant_id = service.tenant_id unless service.tenant_id.nil?
          templ.save
          end
         end
      end
    end  
  end
end
