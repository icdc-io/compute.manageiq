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

    desc "Move services between Users"
    task :move_services_btw_users, [:from_email, :to_email] => :environment do | _, args|
      p args.inspect
      services = Service.where(:evm_owner => User.find_by(:email => args[:from_email]))
      new_owner = User.find_by(:email => args[:to_email])
      services.each do |service|
        service.evm_owner = new_owner
        service.miq_group = new_owner.current_group
        service.vms.each do |vm|
          vm.evm_owner = new_owner
          vm.miq_group = new_owner.current_group
          vm.save!
        end
        service.save!
      end
    end
  end
end
