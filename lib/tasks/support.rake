namespace :support do
  namespace :icdc do
    desc "Move service between Accounts"
    task :transfer_service , [:service_id, :account_id] => :environment do | _, args|
      p args.inspect
      account = Tenant.find(args[:account_id])
      group = account.miq_groups.select{ |x| x.description.include?(".member") }.first
      Service.find(args[:service_id]).update!(:miq_group => group) 
      Service.find(args[:service_id]).vms.each{|vm| vm.update!(:miq_group => group)}
      puts "Complete"
    end
  end
end
