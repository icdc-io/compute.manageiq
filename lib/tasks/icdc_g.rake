namespace :icdc_g do
  desc "Remove remote region data from local database"
  task :catalog_init => :environment do
    for service in ServiceTemplate.all
      if service.name.index("-IDC") || service.name.index("-NB5")
         service.display = "t"
         service.save
      else
        service.display = "f"
        service.save 
      end 
    end
  end
end
