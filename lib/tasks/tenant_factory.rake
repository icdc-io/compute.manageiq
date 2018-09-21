require 'net/http'
require 'json'

module ApiHelper
  def self.find_iba_user(email)
    req = Net::HTTP::Get.new("/users/search?key=e_mail&value=#{email}&access_token=#{get_rest_service_token}")
    return call_iba_rest_service(req)[0]
  end

  def self.find_iba_user_by_id(id)
    req = Net::HTTP::Get.new("/users/search?key=EmployeeID&value=#{id}&access_token=#{get_rest_service_token}")
    response  = call_iba_rest_service(req)
    for person in response
      return person if person["EmployeeID"] == id
    end
  end

  def self.find_iba_department(id)
    req = Net::HTTP::Get.new("/departments/search?key=DepartNumber&value=#{id}&access_token=#{get_rest_service_token}")
    return call_iba_rest_service(req)[0]
  end

  def self.find_group_users(id)
    req = Net::HTTP::Get.new("/users/search?key=DepartNumber&value=#{id}&access_token=#{get_rest_service_token}")
    return call_iba_rest_service(req)[0]
  end

  def self.find_related_departments(level, id)
    req = Net::HTTP::Get.new("/departments/search?key=DepartLevel#{level}&value=#{id}&access_token=#{get_rest_service_token}")
    return call_iba_rest_service(req)
  end

  def self.call_iba_rest_service(req)
    http = Net::HTTP.new("login.icdc.io", "3000")
    return JSON.parse(http.request(req).body)
  end

  def self.get_rest_service_token
    config = YAML.load_file(File.join(Rails.root, "config/iba_rest_service.yaml"))
    return config['token']
  end
end

namespace :tenant_factory do
  desc "Remove remote region data from local database"
  task :create_tenants, [:id] => :environment do |t, args|
    group_id = args[:id]
    iba_group = ApiHelper.find_iba_department(group_id)
    parent_groups = iba_group["DepartUN"]
    related_groups = ApiHelper.find_related_departments(parent_groups.length-1, group_id)
    for group_id in parent_groups
      group = ApiHelper.find_iba_department(group_id)
      next if Tenant.find_by_name(group["SName"])
      if group["DepartUN"].length > 1
        ancestry = ApiHelper.find_iba_department(group["DepartUN"][-2])["SName"]
        ancestry = Tenant.in_region(99).find_by_name(ancestry)
      else
        ancestry = Tenant.in_region(99).find_by_name("My Company")
      end
      tenant = Tenant.new
      tenant.name = tenant.description = group["SName"]
      tenant.description = group["Otdele"]
      tenant.external_id = group["DepartNumber"]
      ancestry_id = "#{ancestry.id}"
      ancestry_id = "#{ancestry.ancestry}/#{ancestry_id}" if ancestry.ancestry
      tenant.ancestry = ancestry_id
      tenant.save!
      `rake users_sync:sync_tenant[#{tenant.id}]`
    end
    for group in related_groups
        next if Tenant.find_by_name(group["SName"]) || ApiHelper.find_group_users(group["DepartNumber"])
        ancestry = ApiHelper.find_iba_department(group["DepartUN"][-2])["SName"]
        ancestry = Tenant.in_region(99).find_by_name(ancestry)
        tenant = Tenant.new
        tenant.name = tenant.description = group["SName"]
        tenant.description = group["Otdele"]
        tenant.external_id = group["DepartNumber"]
        ancestry_id = "#{ancestry.id}"
        ancestry_id = "#{ancestry.ancestry}/#{ancestry_id}" if ancestry.ancestry
        tenant.ancestry = ancestry_id
        tenant.save!
        `rake users_sync:sync_tenant[#{tenant.id}]`
    end
    for group in related_groups
      next if MiqGroup.find_by_description(group["SName"]) || !ApiHelper.find_group_users(group["DepartNumber"])
      ancestry = ApiHelper.find_iba_department(group["DepartUN"][-2])["SName"]
      miq_group = MiqGroup.new
      miq_group.description = group["SName"]
      miq_group.tenant = Tenant.in_region(99).find_by_name(ancestry)
      miq_group.miq_user_role = MiqUserRole.find_by_name("ICDC-user")
      miq_group.long_description = group["Otdele"]
      miq_group.external_id = group["DepartNumber"]
      miq_group.save!
      `rake users_sync:sync_group[#{miq_group.id}]`
   end

  end

  task :add_descriptions, [:id] => :environment do |t, args|
    group_id = args[:id]
    iba_group = ApiHelper.find_iba_department(group_id)
    parent_groups = iba_group["DepartUN"]
    related_groups = ApiHelper.find_related_departments(parent_groups.length-1, group_id)
    for group in related_groups
      next if !Tenant.find_by_name(group["SName"])
      tenants = Tenant.where("name = ?", group["SName"])
      for tenant in tenants
       next unless tenant.in_current_region?
        puts "Tenant"
        puts "#{tenant.id}"

        tenant.description = group["Otdele"]
        tenant.external_id = group["DepartNumber"]
        tenant.save
      end
    end
    for group in related_groups
      next if !MiqGroup.find_by_description(group["SName"])
      miq_groups = MiqGroup.where("description = ?", group["SName"])#find_by_description(group["SName"])
      for miq_group in miq_groups
       next unless miq_group.in_current_region?
        puts "Group"
        puts "#{miq_group.id}"
        puts "#{group['Otdele']}"
        miq_group.long_description = group["Otdele"]
        miq_group.external_id = group["DepartNumber"]
        miq_group.save
      end
    end
  end

  task :update_users => :environment do

    users = User.all
    for user in users
     next unless user.in_current_region?
     record =  ApiHelper.find_iba_user(user.userid)
     #puts "no User #{user.userid} found" unless record
     next if !record || record["DepartNumber"] == user.current_group.external_id
     puts "User #{user.userid}"
     puts "User current dep #{user.current_group.description} id #{user.current_group.external_id}"
     real_dep = MiqGroup.in_my_region.where(external_id: record["DepartNumber"]).first
     puts "User real dep id #{record["DepartNumber"]}"
     user.miq_groups = [real_dep] if real_dep
     user.save
     `rake users_sync:update_user[#{user.id}]`
    end

  end

  desc "Remove remote region data from local database"
  task :create_managers, [:id] => :environment do |t, args|
    group_id = args[:id]
    iba_group = ApiHelper.find_iba_department(group_id)
    parent_groups = iba_group["DepartUN"]
    related_groups = ApiHelper.find_related_departments(parent_groups.length-1, group_id)
    for group in related_groups
      next if !Tenant.find_by_name(group["SName"])
      tenants = Tenant.where("name = ?", group["SName"])
      for tenant in tenants
        cat = Classification.find_by_name('manager')
        chief = ApiHelper.find_iba_user_by_id(group["ChiefId"])
        ar_options = {}
        tag_name = chief['e_mail'].downcase.gsub(/[^a-z]/i, '_')
        options = {:name => "#{tag_name}", :description => "#{chief['e_mail'].downcase}"}
        options.each { |k, v| ar_options[k.to_sym] = v if Classification.column_names.include?(k.to_s) || k.to_s == 'name' }

        puts "Tenant"
        puts "#{tenant.id}"
        puts tenant.tags
        puts "#{tag_name}"
        entry = cat.add_entry(ar_options) unless cat.find_entry_by_name(tag_name)
        Classification.classify_by_tag(tenant, "/managed/manager/#{tag_name}")
      end
    end
    for group in related_groups
      next if !MiqGroup.find_by_description(group["SName"])
      miq_groups = MiqGroup.where("description = ?", group["SName"])#find_by_description(group["SName"])
      for miq_group in miq_groups
        cat = Classification.find_by_name('manager')
        chief = ApiHelper.find_iba_user_by_id(group["ChiefId"])
        ar_options = {}
        tag_name = chief['e_mail'].downcase.gsub(/[^a-z]/i, '_')
        options = {:name => "#{tag_name}", :description => "#{chief['e_mail'].downcase}"}
        options.each { |k, v| ar_options[k.to_sym] = v if Classification.column_names.include?(k.to_s) || k.to_s == 'name' }

        puts "Group"
        puts "#{miq_group.id}"
        puts miq_group.tags
        puts "#{tag_name}"

        entry = cat.add_entry(ar_options) unless cat.find_entry_by_name(tag_name)
        Classification.classify_by_tag(miq_group, "/managed/manager/#{tag_name}")
      end
    end
  end

  desc "Remove remote region data from local database"
  task :apply_quota, [:id, :name, :value] => :environment do |t, args|
    tenant_quota = TenantQuota.new
    tenant_quota.tenant_id = args[:id]
    tenant_quota.name = args[:name]
    tenant_quota.value = args[:value]
    tenant_quota.save!
  end

  desc "Update quota to cpu and memory"
  task :update_quota => :environment do
    quotas = TenantQuota.all
    for quota in quotas
      if quota.name == 'svm_allocated'
         new_mem_quota = TenantQuota.new
         new_mem_quota.tenant_id = quota.tenant_id
         new_mem_quota.name = "mem_allocated"
         new_mem_quota.value = quota.value
         new_mem_quota.save!

         new_cpu_quota = TenantQuota.new
         new_cpu_quota.tenant_id = quota.tenant_id
         new_cpu_quota.name = "cpu_allocated"
         new_cpu_quota.value = quota.value / 4
         new_cpu_quota.save!
         quota.destroy
      end
      if quota.name == 'hours_allocated'
        quota.destroy
      end
      if quota.name == 'storage_allocated'
         quota.value = quota.value / 1024**3
         quota.save
      end
    end
    quotas = UserQuota.all
    for quota in quotas
      if quota.name == 'svm_allocated'
         new_mem_quota = UserQuota.new
         new_mem_quota.user_id = quota.user_id
         new_mem_quota.name = "mem_allocated"
         new_mem_quota.value = quota.value 
         new_mem_quota.save!

         new_cpu_quota = UserQuota.new
         new_cpu_quota.user_id = quota.user_id
         new_cpu_quota.name = "cpu_allocated"
         new_cpu_quota.value = quota.value / 4
         new_cpu_quota.save!
         quota.destroy
      end
      if quota.name == 'hours_allocated'
        quota.destroy
      end
      if quota.name == 'storage_allocated'
         quota.value = quota.value / 1024**3
         quota.save
      end
    end
  end
end
