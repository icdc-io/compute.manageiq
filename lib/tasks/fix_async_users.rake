namespace :users_sync do
  desc "Copy async users to all regions"
  task :fix_async_users => :environment do
    # group users by regions
    users = User.all
    idc_users = []
    nb5_users = []
    main_users = []
    for user in users
      idc_users.push(user) if user.miq_region.description == "idc"
      nb5_users.push(user) if user.miq_region.description == "nb5"
      main_users.push(user) if user.miq_region.description == "main"
    end

    # get users IDC - NB5
    puts "Users IDC - NB5:"
    idc_nb5 = []
    for idc_user in idc_users
      unless nb5_users.any? {|user| user.email == idc_user.email } || idc_user.email.include?("@icdc.io") || idc_user.email.include?("testicdc@iba.by")
        puts "- #{idc_user.email}"
        idc_nb5.push(idc_user)
      end
    end

    # get users NB5 - IDC
    puts "Users NB5 - IDC:"
    nb5_idc = []
    for nb5_user in nb5_users
      unless idc_users.any? {|user| user.email == nb5_user.email } || nb5_user.email.include?("@icdc.io") || idc_user.email.include?("testicdc@iba.by")
        puts "- #{nb5_user.email}"
        nb5_idc.push(nb5_user)
      end
    end

    # get NB5 - Main
    puts "Users NB5 - Main:"
    nb5_main = []
    for nb5_user in nb5_users
      unless main_users.any? { |user| user.email == nb5_user.email} || nb5_user.email.include?("@icdc.io") || idc_user.email.include?("testicdc@iba.by")
        puts "- #{nb5_user.email}"
        nb5_main.push(nb5_user)
      end
    end

    # get Main - NB5
    puts "Users Main - NB5:"
    main_nb5 = []
    for main_user in main_users
      unless nb5_users.any? { |user| user.email == main_user.email} || main_user.email.include?("@icdc.io") || idc_user.email.include?("testicdc@iba.by")
        puts "- #{main_user.email}"
        main_nb5.push(main_user)
      end
    end

    # get IDC - Main
    puts "Users IDC - Main:"
    idc_main = []
    for idc_user in idc_users
      unless main_users.any? { |user| user.email == idc_user.email} || idc_user.email.include?("@icdc.io") || idc_user.email.include?("testicdc@iba.by")
        puts "- #{idc_user.email}"
        idc_main.push(idc_user)
      end
    end

    # get Main - IDC
    puts "Users Main - IDC:"
    main_idc = []
    for main_user in main_users
      unless idc_users.any? { |user| user.email == main_user.email} || main_user.email.include?("@icdc.io") || idc_user.email.include?("testicdc@iba.by")
        puts "- #{main_user.email}"
        main_idc.push(main_user)
      end
    end

    master_to_slave_ids = idc_nb5.map(&:id) + nb5_idc.map(&:id) + main_nb5.map(&:id) + main_idc.map(&:id)

    slave_to_master_ids = nb5_main.map(&:id) + idc_main.map(&:id)
    
    
    Rake::Task["users_sync:sync_user_to_main"].invoke(slave_to_master_ids)
    Rake::Task["users_sync:sync_user"].invoke(master_to_slave_ids)

  end

  desc "Copy users from slave region to main"
  task :sync_user_to_main, [:ids] => :environment do |t, args|
    for u_id in args[:ids]
      puts "ID: #{u_id}"
      user_master = User.find_by_id(u_id)
      user = User.in_my_region.where(userid: user_master.userid).first
      unless user
        user = User.new
        user.userid = user_master.userid
      end
      user.email = user_master.email
      default_group = MiqGroup.in_my_region.find_by_description(MiqGroup.find_by_id(user_master.current_group_id).description)
      if default_group
        user.miq_groups = [default_group]
      else
        user.miq_groups = [MiqGroup.find_by_id(99000000001319)]
      end
      user.name = user_master.name
      user.save!
    end
  end
end