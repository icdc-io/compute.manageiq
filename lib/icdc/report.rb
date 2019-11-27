module Icdc
  class Report
    BASE_REPORT = "my_account"

    def self.grouped_results
      get_result_by_role(User.current_user.current_group.miq_user_role)
    end

    def self.get_result_by_role(role)
      return admin_report if User.current_user.super_admin_user?
      generate_result_hash(get_report_results)
    end

    def self.get_report_results
      reports = MiqReport.where(:name => BASE_REPORT)
      result = []
      reports.each do |report|
        result.push(report.miq_report_results.sort_by(&:created_on).last.result_set)
      end
      final_result = []
      case User.current_user.current_group.miq_user_role.settings
      when nil
        managed_tenants_ids = [User.current_user.current_tenant.regional_tenants.collect(&:id), User.current_user.current_tenant.regional_tenants.collect(&:all_subprojects).collect(&:ids)].flatten
        final_result = result.flatten.select {|i| managed_tenants_ids.include?(i['tenant'])}
      when {:restrictions=>{:vms=>:user}}
        final_result = result.flatten.select {|i| User.current_user.name == i['owner_name']}
      when {:restrictions=>{:vms=>:user_or_group}}
        managed_tenants_ids = [User.current_user.current_tenant.regional_tenants.collect(&:id), User.current_user.current_tenant.regional_tenants.collect(&:all_subprojects).collect(&:ids)].flatten
        final_result = result.flatten.select {|i| managed_tenants_ids.include?(i['tenant'])}
      end
      final_result
    end

    def self.generate_result_hash(results)
      result_set = []
      results.group_by{ |r| r['service_id'] }.each do |service|
        cpu = memory = cost = 0
        disk_type = []
        uptime = []
        h = {}
        next unless Service.find_by_id(service.first)
        h[:id] = service.first
        service_obj = Service.find_by_id(service.first)
        next unless service_obj
        h[:name] = service_obj.name
        h[:owner] = service_obj.evm_owner.name
        tenant =  Tenant.find_by_id(service.second.first['tenant'])
        h[:tenant] = tenant
        h[:project_name] = tenant.project? ? tenant.name : ""
        h[:location] = service_obj.miq_region.description.upcase
        h[:vms] = []
        service.second.each do |vm|
          cpu += vm['cpu_allocated_total']
          memory += vm['memory_allocated_total']
          cost += vm['total_cost'].round(2)
          disk_type << vm['disk_type']
          uptime << vm['uptime']
          h[:vms] << {:name => vm['vm_name'], :cpu => vm['cpu_allocated_total'], :mem => vm['memory_allocated_total'], :cost => vm['total_cost'].round(2), :disk_type => vm['disk_type'], :uptime => vm['uptime']}
        end
        h[:cost] = cost
        h[:cpu] = cpu
        h[:mem] = memory
        h[:uptime] = uptime.sum
        h[:storage] = squash_disks(disk_type)
        h[:backups_size] = service.second.first['backup_disk']
        result_set.push(h)
      end
      {:data => result_set, :total => calculate_total_values(result_set)}
    end

    def self.admin_report
      reports = MiqReport.where(:name => BASE_REPORT)
      result = []
      reports.each do |report|
        result.push(report.miq_report_results.sort_by(&:created_on).last.result_set)
      end
      generate_result_hash(result.flatten.reject { |i| i.empty? })
    end

    private

    def self.squash_disks(disks)
      disks_array = []
      result_hash = {:Fast => 0, :Medium => 0, :Slow => 0}
      disks.each { |d| d.split(";").each { |disk| disks_array << disk.squish } }
      disks_array.reject{|da| da == ""}.each do |disk|
        result_hash[disk.split(":").first.squish.to_sym] += disk.split(":").second.squish.to_i
      end
      result = ""
      result_hash.each_key { |k| result_hash.delete(k) if result_hash[k] == 0 }.each do |k,v|
        result += "#{k} : #{v} Gb;"
      end
      result
    end

    def self.calculate_total_values(result_set)
      total_result = {:total_cpu => 0, :total_mem => 0, :total_storage => 0, :total_backups_size => 0, :total_uptime => 0, :total_cost => 0}
      total_disks = []
      result_set.each do |result|
        total_result[:total_cpu] += result[:cpu]
        total_result[:total_mem] += result[:mem]
        total_result[:total_backups_size] += result[:backups_size].to_i
        total_result[:total_uptime] += result[:uptime]
        total_result[:total_cost] += result[:cost]
        total_disks << result[:storage]
      end
      total_result[:total_storage] = squash_disks(total_disks)
      total_result
    end
  end # end ServiceReportController
end # end API
