namespace :icdc do

desc "OB Templates Renamer"
task :rename_templates => :environment do
  require 'csv'

  SEPARATOR = ';'

  TEMPLATES_NAME_MAP_FILE = Rails.root.join("tmp", "cats.csv")

  TEMPLATES_NAME_MAP_CSV = CSV.read(TEMPLATES_NAME_MAP_FILE, {:col_sep => SEPARATOR})

  templates_name_map = {}

  TEMPLATES_NAME_MAP_CSV.each do |cat|
    templates_name_map[cat[1]&.strip] = "#{cat[2]&.strip}:#{cat[3]&.strip}"
  end

  success = []
  fails = []

  templates_name_map.each do |old_name, new_name|
    regions = MiqRegion.all.map(&:description).map(&:upcase)

    regions.each do |region|
      st = ServiceTemplate.where(name: "#{old_name}-#{region}").first
      if st
        st.name = "#{new_name}:#{region}"
        st.save
        success << {old_name => new_name}
        puts "Template #{old_name} changed name to #{new_name}"
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

desc "Restart DEV app shortcut"
task :restart => :environment do
  Rake::Task['icdc:dev:restart'].invoke
end

namespace :dev do
  desc "Delete all miq_schedules after deployment of DEV environment"
  task :remove_schedules => :environment do
    MiqSchedule.where('description NOT LIKE ?', 'rss_%').where('description NOT LIKE ?', 'report_%').where('description NOT LIKE ?', 'chart_%').where('description NOT LIKE ?', 'tenant_%').delete_all
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

end
end
