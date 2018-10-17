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

desc "Restart DEV app shortcut"
task :restart => :environment do
  Rake::Task['icdc:dev:restart'].invoke
end

namespace :dev do
  desc "Delete all miq_schedules after deployment of DEV environment"
  task :remove_schedules => :environment do
    MiqSchedule.where('description NOT LIKE ?', 'rss_%').where('description NOT LIKE ?', 'report_%').where('description NOT LIKE ?', 'chart_%').where('description NOT LIKE ?', 'tenant_%').delete_all
  end

  desc "Restart DEV app shortcut"
  task :restart => :environment do
    Rake::Task['evm:stop'].invoke
    `pkill -9 httpd`
    `ipcs -s | awk -v user=apache '$3==user {system("ipcrm -s "$2)}'`
    puts "Starting MiqServer"
    `ruby /var/www/miq/vmdb/lib/workers/bin/evm_server.rb &`
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
    puts "[fix_cb_seeding] ChargeableField.all: #{ChargeableField.all.count}"
    ChargeableField.all.collect{|x| {id: x.id, crdm_id: x.chargeback_rate_detail_measure_id, metric: x.metric} }.each{|x| puts x}    
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
  end

  desc "Adjust pglogical host and port for different openshift environments"
  task :pglogical_openshift, [:env] => :environment do |_, args|
    region_map = { "region_1" => :idc, "region_2" => :nb5, "region_99" => :main }
    openshift_map = {
      stage: {
        nb5: { host: "miq-nb5-master.icdc.io", port: "31120" }
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

end


end
