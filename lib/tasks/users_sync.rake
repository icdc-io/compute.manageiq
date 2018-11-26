namespace :users_sync do
  desc "Remove remote region data from local database"
  task :sync_all => :environment do
    users = User.all
    users = users.as_json
    for user in users
      user['miq_group'] = MiqGroup.find_by_id(user['current_group_id']).description
    end
    groups = MiqGroup.all
    groups_arr = []
    for group in groups
      group_hash = group.as_json
      group_hash['miq_user_role'] = group.miq_user_role.name unless group.group_type == 'tenant'
      groups_arr.push(group_hash)
    end
    groups = groups_arr
    regions = PglogicalSubscription.find(:all).map{|region| region.find_pass}
    for region in regions
      conn = ActiveRecord::Base.establish_connection("postgres://#{region.user}:#{region.password}@#{region.host}/#{region.dbname}")
      conn.connection.execute("DELETE from users")
      conn.connection.execute("DELETE from miq_groups_users")
      conn.connection.execute("DELETE from miq_groups")
      for group_master in groups
        group = MiqGroup.new
        group.id = group_master['id'] - 99000000000000 + region.provider_region * 1000000000000
        group.description = group_master['description']
        group.group_type = group_master['group_type']
        group.miq_user_role = MiqUserRole.find_by_name(group_master['miq_user_role'])
        group.tenant_id = group_master['tenant_id'] - 99000000000000 + region.provider_region * 1000000000000
        group.save!
      end
      for user_master in users
        user = User.new
        user.id = user_master['id'] - 99000000000000 + region.provider_region * 1000000000000
        user.userid = user_master['userid']
        user.email = user_master['email']
        default_group = MiqGroup.find_by_description(user_master['miq_group'])
        user.miq_groups = [default_group]
        user.name = user_master['name']
        user.password = 'smartvm'
        user.save!
      end
    end
  end

  desc "Remove remote region data from local database"
  task :sync_user, [:id] => :environment do |t, args|
    user_master = User.find_by_id(args[:id]).as_json
    user_master['miq_group'] = MiqGroup.find_by_id(user_master['current_group_id']).description
    regions = PglogicalSubscription.find(:all).map{|region| region.find_pass}
    for region in regions
      conn = ActiveRecord::Base.establish_connection("postgres://#{region.user}:#{region.password}@#{region.host}/#{region.dbname}")
      user = User.where(userid: user_master['userid']).first
      unless user
        user = User.new
        user.userid = user_master['userid']
      end
      user.email = user_master['email']
      default_group = MiqGroup.find_by_description(user_master['miq_group'])
      user.miq_groups = [default_group]
      user.name = user_master['name']
      user.save!
      conn.connection.close
    end
  end

  desc "Remove remote region data from local database"
  task :update_user, [:id] => :environment do |t, args|
    user_master = User.find_by_id(args[:id]).as_json
    user_master['miq_group'] = MiqGroup.find_by_id(user_master['current_group_id']).description
    regions = PglogicalSubscription.find(:all).map{|region| region.find_pass}
    for region in regions
      conn = ActiveRecord::Base.establish_connection("postgres://#{region.user}:#{region.password}@#{region.host}/#{region.dbname}")
      user = User.where(userid: user_master['userid']).first
      unless user
        user = User.new
        user.id = user_master['id'] - 99000000000000 + region.provider_region * 1000000000000
        user.userid = user_master['userid']
      end
      user.email = user_master['email']
      default_group = MiqGroup.find_by_description(user_master['miq_group'])
      user.miq_groups = [default_group]
      for vm in user.vms
        vm.miq_group_id = default_group.id
        vm.save!
        service = vm.service
        if service
          service.miq_group = default_group
          service.save!
        end
      end
      user.name = user_master['name']
      user.save!
      conn.connection.close
    end
  end

  desc "Remove remote region data from local database"
  task :sync_group, [:id] => :environment do |t, args|
    group_master = MiqGroup.find_by_id(args[:id]).as_json
    group_master['tenant_name'] = Tenant.find_by_id(group_master['tenant_id']).name
    regions = PglogicalSubscription.find(:all).map{|region| region.find_pass}
    for region in regions
      conn = ActiveRecord::Base.establish_connection("postgres://#{region.user}:#{region.password}@#{region.host}/#{region.dbname}")
      group = MiqGroup.new
      group.id = group_master['id'] - 99000000000000 + region.provider_region * 1000000000000
      group.tenant = Tenant.find_by_name(group_master['tenant_name'])
      group.description = group_master['description']
      group.miq_user_role = MiqUserRole.find_by_name("ICDC-user")
      group.save!
      conn.connection.close
    end
  end

  desc "Remove remote region data from local database"
  task :sync_tenant, [:id] => :environment do |t, args|
    tenant_master = Tenant.find_by_id(args[:id]).as_json
    regions = PglogicalSubscription.find(:all).map{|region| region.find_pass}
    for region in regions
      conn = ActiveRecord::Base.establish_connection("postgres://#{region.user}:#{region.password}@#{region.host}/#{region.dbname}")
      tenant = Tenant.new
      tenant.id = tenant_master['id'] - 99000000000000 + region.provider_region * 1000000000000
      tenant.ancestry = tenant_master['ancestry'].split('/').map{ |x| x.sub("99", "#{region.provider_region}")}.join("/")
      tenant.name = tenant_master['name']
      tenant.save!
      conn.connection.close
    end
  end
end
