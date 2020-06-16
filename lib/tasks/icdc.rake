namespace :icdc do

desc "OB Templates Renamer"
task :rename_templates => :environment do
  require 'csv'

  SEPARATOR = ';'

  TEMPLATES_NAME_MAP_FILE = Rails.root.join("tmp", "cats.csv")

  TEMPLATES_NAME_MAP_CSV = CSV.read(TEMPLATES_NAME_MAP_FILE, {:col_sep => SEPARATOR})

  templates_name_map = {}

  CATEGORIES = ["Content Management", "Development Tools", "Databases", "Distributions", "Misc Apps"]

  last_category = nil
  new_cat_id = nil

  TEMPLATES_NAME_MAP_CSV.each do |row|
    if CATEGORIES.include?(row[0])
      last_category = row[0]
      new_cat_id = ServiceTemplateCatalog.find_or_create_by(name: last_category).id
    end

    templates_name_map[row[1]&.strip] = {name: "#{row[2]&.strip}:#{row[3]&.strip}", cat_id: new_cat_id }
  end


  success = []
  fails = []

  templates_name_map.each do |old_name, new_info|
    regions = MiqRegion.all.map(&:description).map(&:upcase)

    regions.each do |region|
      st = ServiceTemplate.where(name: "#{old_name}-#{region}").first || ServiceTemplate.where(name: "#{new_info[:name]}-#{region}").first || ServiceTemplate.where(name: "#{new_info[:name]}").first || ServiceTemplate.where(name: "#{new_info[:name]}:#{region}").first
      if st
        st.name = "#{new_info[:name]}:#{region}"
        st.service_template_catalog_id = new_info[:cat_id]
        st.save
        success << {old_name => new_info}
        puts "Template #{old_name} changed name to #{new_info}"
      else
        fails << old_name
        puts "Template #{old_name} not found"
      end
    end

  end

  puts "success: #{success}"
  puts "fails: #{fails}"
end

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

desc "Create service for new vm"
task :service_for_new_vm, [:service_name, :user_id, :vm_id] => :environment do | _, args|
  begin
    service = Service.new
    service.name = args[:service_name]
    owner = User.find(args[:user_id])
    service.evm_owner = owner
    service.miq_group = owner.current_group
    service.save!
    VmOrTemplate.find(args[:vm_id]).add_to_service(service)
    VmOrTemplate.find(args[:vm_id]).update!(:evm_owner => owner)
    VmOrTemplate.find(args[:vm_id]).update!(:miq_group => owner.current_group)
    puts "New service #{service.name} creation finished completed"
  rescue => e
    puts "New service creatin failed with error => #{e.message}"
  end
end

desc "Move Service to new Account"
task :move_service, [:name, :account] => :environment do |_, args|
  begin
    service = Service.find_by_name(args[:name])
    service ||= VmOrTemplate.find_by_name(args[:name]).service
    account = Tenant.find_by(:name => args[:account])
    service.tenant = account
    service.miq_group = account.miq_groups.select{|mg| mg.name.include?("member")}.first
    service.save!
    service.vms.each do |vm|
      vm.tenant = account
      vm.miq_group = account.miq_groups.select{|mg| mg.name.include?("member")}.first
      vm.save!
    end
  rescue => e
    puts "Can't move service, because #{e.message}"
  end
end

desc "Rename ICDC-members -> ICDC-member"
task :rename_member_groups => :environment do
  MiqGroup.in_my_region.each do |mg|
    next if mg.tenant_group?
    mg.update(:description => mg.description[0..-2]) if mg.description.include?("members")
  end
  MiqUserRole.in_my_region.find_by_name("ICDC-members").update(:name => "ICDC-member")
end

desc "Restart DEV app shortcut"
task :restart => :environment do
  Rake::Task['icdc:dev:restart'].invoke
end

desc "Create onering account"
task :relocate_users => :environment do
  Tenant.in_my_region.all.each do |x|
    begin
      childrens = []
      users = []
      managers = []
      find_all_children(childrens, x)
      #Find all tenant users
      #Manager have 2 group in tenant (member and manager (admin or billing))
      childrens.reject { |c| c.empty? }.flatten.each do |tenant|
        managers.push(tenant.managers)
        users.push(tenant.users)
        new_tenant = find_parent_tenant(tenant)
        user_transfer(users.reject{|u| u.empty?}.flatten, managers.reject{|m| m.empty?}.flatten, new_tenant)
      end 
    rescue => e
      p "ERROR! #{x.description} :: #{e.message}"
      next
    end
  end
  p "Setting tenant quotas"
  set_tenant_quotas
  p "Exchange quota values from Gb ti Bytes"
  exchange_quota_values
  p "Patching services"
  patch_services_and_vms
  p "Setting tenant networks"
  set_tenant_networks
end

public 

def find_all_children(childrens, tenant)
  childrens.push(tenant.children)
    tenant.children.each{|x| x.find_all_children(childrens, x)}
end

def find_parent_tenant(tenant)
  Tenant.in_my_region.find((tenant.ancestry.split("/") - %w(2000000000001 2000000000054 1000000000001 1000000000054 99000000000001 99000000000054)).first)
end

def user_transfer(users, managers, tenant)
  members_group = find_new_group(tenant.description, "members")
  manager_group = find_new_group(tenant.description, "billing")
  users.each do |user|
    next if user.userid == "admin"
    user.miq_groups = [ members_group ]
    user.current_group = members_group
    user.save!
  end

  
  managers.each do |manager|
    manager.miq_groups = []
    manager.miq_groups = [members_group, manager_group]
    manager.current_group = members_group
    manager.save!
  end

end

def find_new_group(description, role)
  Tenant.in_my_region.where(:description => description).where("name NOT LIKE?", "t_%").first.miq_groups.select{ |g| g.description.include?(role) }.first
end

def change_miq_user_roles
    MiqGroup.in_my_region.where("description NOT LIKE?","g_%").each do |group|
      next if group.description.start_with?("Evm")
      group.miq_user_role = MiqUserRole.in_my_region.find_by_name("ICDC-#{group.description.split(".").last}")
    end 
end

def set_tenant_quotas
  accounts = Tenant.in_my_region.all.select{|t| t.account?}
  accounts.each do |account|
    Tenant.in_my_region.where(:description => account.description).where("name NOT LIKE?", "t_%").first.tenant_quotas.push(account.tenant_quotas)
  end
end

def exchange_quota_values
  Tenant.in_my_region.where("name NOT LIKE?", "t_%").each do |tenant|
    tenant.tenant_quotas.map do |quota|
      next if quota.name == "cpu_allocated"
      quota.value = quota.value * (1024 ** 3)
      quota.save!
    end
  end 
end

def set_tenant_networks
  Tenant.in_my_region.where("name LIKE?", "t_%").each do |tenant|
    tenant.tags.each do |tag|
      Tenant.in_my_region.where(:description => tenant.description).where("name NOT LIKE?", "t_%").first.tags.push(tag) if /\/managed\/networks\// =~ tag.name
    end
  end
end

def patch_services_and_vms
  User.in_my_region.all.each do |user|
    Service.in_my_region.where(:evm_owner => user).each do |service|
      service.update!(:miq_group => user.current_group)
      service.vms.each do |vm|
        vm.update!(:miq_group => user.current_group)
      end
    end
  end
end

namespace :dev do
  desc "Delete all miq_schedules after deployment of DEV environment"
  task :remove_schedules => :environment do
    MiqSchedule.where('description NOT LIKE ?', 'rss_%').where('description NOT LIKE ?', 'report_%').where('description NOT LIKE ?', 'chart_%').where('description NOT LIKE ?', 'tenant_%').delete_all
    Service.all.map{|x| x.update!(:retires_on => nil)}
  end

  desc "Disabling C&U collection for EmsClusters in NB5"
  task :disable_perf_capture => :environment do
    puts "Disable C&U collection"
    Metric::Targets.perf_capture_always = {:storage => false, :host_and_cluster => false}
    perf_tag_id = Tag.where(:name => "/performance/capture_enabled").first.id
    EmsCluster.find_tagged_with(:all => "capture_enabled", :ns => "/performance").each do |cluster|
      perf_tagging = cluster.taggings.where(tag_id: perf_tag_id)&.first
      perf_tagging.destroy! if perf_tagging
    end
    Storage.find_tagged_with(:all => "capture_enabled", :ns => "/performance").each do |datastore|
      perf_tagging = datastore.taggings.where(tag_id: perf_tag_id)&.first
      perf_tagging.destroy! if perf_tagging
    end
  end 

  desc "Fix replication ticket#8082"
  task :replica_fix => :environment do
    puts "Fixing replication..."
    location = MiqRegion.my_region.description.downcase.to_s
    puts "[replica_fix] location: #{location}"
    case location
    when "main"
      puts "MAIN"
      regions = PglogicalSubscription.find(:all).map{|region| region.find_pass}
      for region in regions
        ex=0
        max=0
        until ex==1 || max < 300
          sleep(1)
          puts " #{region.host}"
          conn = ActiveRecord::Base.establish_connection("postgres://#{region.user}:#{region.password}@#{region.host}:#{region.port}/#{region.dbname}")
          conn.connection
          max+=1
          ex=1 if conn.connected?
        end
      end
        ActiveRecord::Base.connection.execute("select pglogical.alter_subscription_enable('region_1_subscription');")
        ActiveRecord::Base.connection.execute("select pglogical.alter_subscription_enable('region_2_subscription');")
    when "idc"
      puts "IDC"
      ActiveRecord::Base.connection.execute("select * from pg_create_logical_replication_slot('pgl_vmdb_production_region_1_region_116df111', 'pglogical_output')")
    when "nb5"
      puts "NB5"
      ActiveRecord::Base.connection.execute("select * from pg_create_logical_replication_slot('pgl_vmdb_production_region_2_region_2110c88d', 'pglogical_output')")
    else
      puts "unknown region"
    end
  end

  desc "Restart DEV app shortcut"
  task :restart => :environment do
    `pkill -9 httpd`
    `ipcs -s | awk -v user=apache '$3==user {system("ipcrm -s "$2)}'`
    Rake::Task['evm:stop'].invoke
    puts "Starting MiqServer"
    Rake::Task['evm:start'].invoke
  end

  desc "Show Slave catalog items"
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

  desc "Set log level in Vmdb::Settings"
  task :log_level, [:log_name, :level_value] => :environment do |_, args|
    name = args[:log_name].to_sym
    value = args[:level_value]
    setting = {log: {name => value}}
    Vmdb::Settings.save!(MiqServer.in_my_region.first, setting)
    # Vmdb::Settings.reload! ## currently we do not need a reload
  end

  desc "Setup separate credentials for DEV environment"
  task :redhat_creds, [:env] => :environment do |_, args|
    if args.nil? or args[:env].nil?
      abort("Provide env name. For example: rake #{_}[dev3]")
    end
    env = args[:env].to_sym
    location = MiqRegion.my_region.description.downcase.to_sym
    puts "[redhat_creds] env:#{env}"
    puts "[redhat_creds] location:#{location}"
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
    cred = creds.dig(location, env)
    if cred.nil?
      abort("Credentials not specified for location[#{location}] and environment[#{env}]")
    end
    provider = ManageIQ::Providers::Redhat::InfraManager.first
    auth = provider.authentications.where(authtype: "default").first
    auth.userid = cred[:userid]
    auth.password = cred[:password]
    auth.save
  end

  desc "Cross openshift urls on production"
  task :fix_ws_url => :environment do
    env = ENV["MY_POD_NAMESPACE"][4..-1].to_sym #dev1, dev2, dev3, dev4, prod
    location = MiqRegion.my_region.description.downcase.to_sym
    puts "[fix_ws_url] env:#{env}"
    puts "[fix_ws_url] location:#{location}"
    urls = {
      idc: {
        dev1: "https://httpd-idc-miq-dev1.dev.icdc.io",
        dev2: "https://httpd-idc-miq-dev2.dev.icdc.io",
        dev3: "https://httpd-idc-miq-dev3.dev.icdc.io",
        dev4: "https://httpd-idc-miq-dev4.dev.icdc.io",
	prod: "https://miq-idc.icdc.io"
      },
      nb5: {
        dev1: "https://httpd-nb5-miq-dev1.dev.icdc.io",
        dev2: "https://httpd-nb5-miq-dev2.dev.icdc.io",
        dev3: "https://httpd-nb5-miq-dev3.dev.icdc.io",
        dev4: "https://httpd-nb5-miq-dev4.dev.icdc.io",
	prod: "https://miq-nb5.icdc.io"
      },
      main: {
        dev1: "https://httpd-main-miq-dev1.dev.icdc.io",
        dev2: "https://httpd-main-miq-dev2.dev.icdc.io",
        dev3: "https://httpd-main-miq-dev3.dev.icdc.io",
        dev4: "https://httpd-main-miq-dev4.dev.icdc.io",
	prod: "https://miq-main.icdc.io"
      },
    }
    url = urls.dig(location, env)
    if urls.nil?
      abort("Webservices url is not specified for location[#{location}] and environment[#{env}]")
    end
    setting = {webservices: {url: url}}
    Vmdb::Settings.save!(MiqServer.in_my_region.first, setting)
  end


  desc "Setup separate credentials for DEV environment"
  task :redhat_tls_off, [:env] => :environment do |_, args|
    provider = ManageIQ::Providers::Redhat::InfraManager.first
    #self-signed certificate for RHV systems
    provider.default_endpoint.update_attributes(verify_ssl: 0)
  end

  desc "Remove all ChargeableField after migration of backup data"
  task :fix_cb_field, [:env] => :environment do |_, args|
    puts "[fix_cb_field] ChargeableField.all: #{ChargeableField.all.count}"
    ChargeableField.delete_all
  end

  desc "Remove all ChargebackRateDetail data, as it cause migration fault"
  task :fix_cb_seeding, [:env] => :environment do |_, args|
    puts "[fix_cb_seeding] ChargebackRateDetail.all: #{ChargebackRateDetail.all.count}"
    puts "[fix_cb_seeding] ChargebackRateDetailMeasure.all: #{ChargebackRateDetailMeasure.all.count}"
    puts "[fix_cb_seeding] ChargebackTier.all: #{ChargebackTier.all.count}"
    ## We do not have ChargeableField before migration finished
    ##puts "[fix_cb_seeding] ChargeableField.all: #{ChargeableField.all.count}"
    ##ChargeableField.all.collect{|x| {id: x.id, crdm_id: x.chargeback_rate_detail_measure_id, metric: x.metric} }.each{|x| puts x}
    #Seeding failed with migration 20170109142011_extract_field_data_from_rate_detail.rb
    #It migrates ChargebackRateDetail default data to ChargeableField objects
    #But for MAIN server (with replica of slave servers) it creates MAIN ChargeableField object for Slave entries
    ChargebackRateDetail.delete_all
    puts "[fix_cb_seeding] all ChargebackRateDetail deleted"
    ChargebackRateDetailMeasure.delete_all
    puts "[fix_cb_seeding] all ChargebackRateDetailMeasure deleted"
    #Seeding creates a lot of ChargebackTier on each container run
    ChargebackTier.delete_all
    puts "[fix_cb_seeding] ChargebackTier after delete_all"
    ChargebackRate.delete_all
    puts "[fix_cb_seeding] all ChargebackRate deleted"
  end

  desc "Activate MiqServer role"
  task :activate_role, [:role] => :environment do |_,args|
    if args.nil? or args[:role].nil?
      abort("Provide valid MiqServer role name. For example: rake #{_}[cockpit_ws]")
    end
    server = MiqServer.in_my_region.first
    roles = server.settings_for_resource.server.role.split(",")
    roles.push(args[:role])
    setting = {server: {role: roles.sort.join(",")}}
    Vmdb::Settings.save!(MiqServer.in_my_region.first, setting)
  end

  desc "Deactivate MiqServer role"
  task :deactivate_role, [:role] => :environment do |_,args|
    if args.nil? or args[:role].nil?
      abort("Provide list of valid MiqServer role names. For example: rake #{_}[cockpit_ws]")
    end
    server = MiqServer.in_my_region.first
    roles = server.settings_for_resource.server.role.split(",") - [ args[:role] ]
    setting = {server: {role: roles.sort.join(",")}}
    Vmdb::Settings.save!(MiqServer.in_my_region.first, setting)
    MiqServer.my_server.deactivate_roles(args[:role])
  end

  desc "Fix storing of metrics on glusterFS"
  task :fix_glufs_metrics => :environment do
    Vmdb::Settings.save!(MiqServer.in_my_region.first, 
      {
        :session => {
         :log_threshold => "10000.kilobytes", 
         :element_threshold => "1000.kilobytes"
        }
      }
    )
  end

  desc "Adjust pglogical host and port for different openshift environments"
  task :pglogical_openshift, [:env] => :environment do |_, args|
    region_map = { "region_1" => :idc, "region_2" => :nb5, "region_99" => :main }
    openshift_map = {
      stage: {
        nb5: { host: "miq-nb5-master.icdc.io", port: "31120" }
      },
      prod: {
        nb5: { host: "miq-nb5-master.icdc.io", port: "31020" }
      }
    }
    deploy_env = ENV["MY_POD_NAMESPACE"][4..-1].to_sym #dev1, dev2, dev3, dev4
    openshift_map = openshift_map[deploy_env] #hostname:port map for specific project
    pglogical = ApplicationRecord.connection.pglogical
    pglogical.nodes.to_a.each do |node|
      location = region_map[ node["name"] ]
      cross_cluster_conn = openshift_map ? openshift_map[location] : nil
      attrs = node["conn_string"].split(" ").map do |p|
        if p.start_with?("host=")
          unless cross_cluster_conn
            "host='postgresql-#{location}'"
          else
            "host='#{cross_cluster_conn["host"]}'"
          end
        elsif p.start_with?("port=")
          unless cross_cluster_conn
            "port='5432'"
          else
            "port='#{cross_cluster_conn["port"]}'"
          end
        else
          p
        end
      end
      conn_string = " " + attrs.join(" ")
      puts "Update pglogical node_dsn #{node["name"]}:#{conn_string}"
      pglogical.node_dsn_update(node["name"], conn_string)
    end
  end

  desc "Next 2 tasks assign new provision dialog and new retirement methods to templates"
  task :retirement_methods => :environment do
    for action in ResourceAction.all
     if (action.action == 'Retirement' && action.resource_type == 'ServiceTemplate')
       if action.ae_instance == 'RHEVService1VM'
         action.ae_instance = 'Service_redhat'
       elsif action.ae_instance == 'Service1VM'
         action.ae_instance = 'Service_vmware'
       elsif action.ae_instance == 'Default'
         action.ae_instance = 'Service_generic'
       end
      end
      action.save
     end
   end

  task :dialog_assignment => :environment do
      for action in ResourceAction.all
        if (action.resource_type == 'ServiceTemplate')
          action.dialog_id = Dialog.where(name: 'SimpleService_new').first.id
        end
        action.save
      end
  end

  desc "ICDC temporarily solution: We need to install haikunator latest version (from github)"
  task :fix_haikunator => :environment do
   `git clone https://github.com/usmanbashir/haikunator.git /var/www/miq/haikunator; \
    cd /var/www/miq/haikunator; rake build; gem install pkg/haikunator-1.1.0.gem; rm -rf /var/www/miq/haikunator`
  end

end
end
