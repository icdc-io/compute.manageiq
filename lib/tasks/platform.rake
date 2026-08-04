namespace :platform do
  # Users that do not belong to any tenant (i.e. have no group, hence no tenant)
  # are moved to the "demo" account by placing them in the "demo.member" group,
  # which puts them in that group's tenant.
  #
  # If such a user still owns an active Vm or Service, we do NOT touch them and
  # instead print a warning so they can be processed manually.
  #
  #   Options (env vars):
  #     DEMO_GROUP=<description>  group to assign to (default: "demo.member")
  #     DRY_RUN=1                 only report what would be done, change nothing
  #
  desc "Assign users without a tenant to the demo account"
  task :fix_lost_users => :environment do
    demo_group_name = ENV["DEMO_GROUP"].presence || "demo.member"
    dry_run         = ENV["DRY_RUN"].present?

    demo_group = MiqGroup.in_my_region.find_by(:description => demo_group_name)
    abort("ERROR: group '#{demo_group_name}' not found in this region") unless demo_group

    demo_tenant = demo_group.tenant

    puts "Demo group: '#{demo_group.description}' (id=#{demo_group.id}), tenant '#{demo_tenant.name}'"
    puts "DRY RUN - no changes will be saved" if dry_run
    puts "-" * 60

    assigned = 0
    warned   = 0
    lost     = 0

    User.in_my_region.includes(:miq_groups).find_each do |user|
      next if user.admin?
      next unless user.tenants.empty?

      lost += 1

      active_vms      = user.vms.select(&:active?)
      active_services = platform_active_services_for(user)

      if active_vms.any? || active_services.any?
        warned += 1
        puts "WARNING: process '#{user.userid}' (#{user.email}) manually - " \
             "owns #{active_vms.count} active VM(s) and #{active_services.count} active service(s)"
        next
      end

      if dry_run
        puts "Would assign '#{user.userid}' (#{user.email}) to '#{demo_tenant.name}'"
      else
        user.miq_groups |= [demo_group]
        user.current_group = demo_group
        user.save!
        puts "Assigned '#{user.userid}' (#{user.email}) to '#{demo_tenant.name}'"
      end
      assigned += 1
    end

    puts "-" * 60
    puts "Users without a tenant: #{lost}"
    puts "#{dry_run ? 'Would be assigned' : 'Assigned'} to '#{demo_tenant.name}': #{assigned}"
    puts "Flagged for manual processing: #{warned}"
  end

  # A service still counts as "active" while it is being provisioned or is
  # provisioned and not retired.
  def platform_active_services_for(user)
    Service.in_my_region
           .where(:evm_owner_id => user.id, :retired => [nil, false])
           .select { |s| s.provisioned? || s.lifecycle_state == "provisioning" }
  end
end
