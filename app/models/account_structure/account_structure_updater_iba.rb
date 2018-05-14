require 'erb'
require 'passgen'

class AncestryError < StandardError
end

class AccountStructure::AccountStructureUpdaterIBA
  include ApiHelperIBA


  def initialize()
    @accounts = []
    @accounts_infokadry = []
    @departments_infokadry = []

    @lost_users = []
  end

  def update_structure
    
    begin
      log_start_timestamp

      User.tags2emails(true)

      update_users_emails

      $asu_log.info("finding accounts ...")
      find_accounts
      log_accounts
      
      $asu_log.info("getting accounts from infokadry ...")
      get_accounts_infokadry

      $asu_log.info("getting departments from infokadry ...")
      get_departments_infokadry
      
      $asu_log.info("adding tenants ...")
      add_tenants

      $asu_log.info("adding managers ...")
      add_managers

      $asu_log.info("updating tenants ...")
      update_tenants

      $asu_log.info("deleting not account users ...")
      delete_not_account_users

      $asu_log.info("relocating users ...")
      relocate_users

      $asu_log.info("deleting lost users ...")
      delete_lost_users

      $asu_log.info("deleting lost tenants ...")
      delete_lost_tenants

      $asu_log.info("the update is completed \n")
    rescue => e
      $asu_log.error(e.to_s)
    end
  end

  def self.run_asu
    self.new.update_structure
  end

  def find_accounts
    @accounts = Tenant.in_my_region.where.not(external_id: nil).
                includes(:tags).select { |tenant| tenant.account? }
  end

  def get_accounts_infokadry
    @accounts_infokadry = @accounts.map { |account| find_iba_department(account.external_id) }
  end

  def get_departments_infokadry
    @accounts_infokadry.each do |account_dep|
      subtree_list = dep_subtree_list(dep_level(account_dep), account_dep[DEP_NUMBER])
      @departments_infokadry.push(*subtree_list)
    end

    @departments_infokadry.delete_if do |dep| 
      unless valid_ancestry?(dep)
        msg = "tenant #{dep[DEP]} (#{dep[DEP_NUMBER]}) "\
              "has no ancestor #{dep[ANCESTORS][-2]},"\
              "tenant would be skipped"
        $asu_log.error(msg)
        
        create_support_ticket("ASU: Infokadry tenant ancestor is missing", msg)

        true
      end
    end
  end

  def add_tenants
    @departments_infokadry.each do |dep|
      if find_tenant_by_ext_id(dep[DEP_NUMBER]).nil?
        $asu_log.info("adding tenant #{dep[DEP]} (#{dep[DEP_NUMBER]})")
        add_tenant(dep)
      end
    end
  end

  def add_managers
    @departments_infokadry.each do |dep|
      
      if dep[CHIEF_ID].nil?
        create_support_ticket("ASU: department #{dep[DEP_NUMBER]} has no manager",
        "Infokadry department has no manager: \n #{dep}")

        next
      end

      if find_user_by_employee_id(dep[CHIEF_ID]).nil?
        create_manager(dep[CHIEF_ID])
      end
    end
  end

  def find_user_by_employee_id(employee_id)
    user_infokadry = find_iba_user_by_id(employee_id)
    user_infokadry.present? ? User.in_my_region.find_by(email: user_infokadry[EMAIL].downcase) : nil
  end

  def update_tenants
    update_each_tenant(@accounts_infokadry)
    update_each_tenant(@departments_infokadry)
  end

  def update_each_tenant(tenants)
    tenants.each do |dep|
      tenant = find_tenant_by_ext_id(dep[DEP_NUMBER])
     
      update_single_tenant(dep, tenant)
      update_tenant_manager(dep, tenant)
    end
  end

  def icdc_user_role
    @icdc_user_role ||= MiqUserRole.find_by_name("ICDC-user")
  end

  def update_users_group(tenant)
    default_users_group = tenant.default_users_group
    updated_group_name = generate_group_name(tenant.external_id)

    if default_users_group.nil?
      $asu_log.info("creating default users group for tenant #{tenant.description}")
      tenant.create_users_group
    else
      default_users_group.description = updated_group_name
      default_users_group.miq_user_role = icdc_user_role

      if default_users_group.changed?
        $asu_log.info("updating default users group for tenant #{tenant.description}")
        log_model_changes(default_users_group.description ,default_users_group)
        default_users_group.save!
      end

    end
  end

  def log_model_changes(label, model)
    model.changes.each do |key, change|
      $asu_log.info("#{label}: #{key} changed from #{change[0]} to #{change[1]}")
    end
  end

  def update_single_tenant(dep, tenant)
    updated_name = generate_tenant_name(tenant.external_id)
    updated_ancestry = build_ancestry_with_infocadry(dep)

    tenant.name = updated_name
    tenant.description = dep[DEP]
    tenant.ancestry = updated_ancestry

    if tenant.changed?
      $asu_log.info("updating tenant #{tenant.description} (#{tenant.external_id})")
      log_model_changes(tenant.name, tenant)
      tenant.save!
    end

    update_users_group(tenant)
  end

  def update_tenant_manager(dep, tenant)
    return unless dep[CHIEF_ID].present?
    
    user_infocadry = find_iba_user_by_id(dep[CHIEF_ID])
    return if user_infocadry.nil?

    managers_tags = tenant.tags.select { |tag| tag.name =~ /\/managed\/manager\// }

    delete_ids = tenant.managers_tags.select do |manager_tag|
      find_iba_user(Tenant.email_from_tag(manager_tag)).nil?
    end.map{ |manager_tag| manager_tag.classification&.id }.compact

    actual_manager_classif = actual_manager_classification(user_infocadry)
    delete_ids.delete(actual_manager_classif.id)

    Classification.bulk_reassignment({:model      => 'Tenant',
                                      :object_ids => [tenant.id],
                                      :add_ids    => [actual_manager_classif.id],
                                      :delete_ids => delete_ids
                                     })
  end

  def actual_manager_classification(user_infocadry)
    email = user_infocadry[EMAIL].downcase
    tagged_email = User.email2tag(user_infocadry[EMAIL])

    old_classif = Classification.in_my_region.find_by(description: email)

    if old_classif.present?
      old_classif
    else
      begin
        Classification.in_my_region.find_by_name("manager").entries.create(name: tagged_email,
                                                                          description: email)
      rescue NoMethodError => e
        create_support_ticket("ASU: there is no manager category",
          "there is no manager category in #{Tenant.my_region_number} location,
          please create it before script running")

        raise "there is no manager category, please create it before script running"
      end
    end
  end

  def find_user_group(tenant_ext_id)
    tenant = find_tenant_by_ext_id(tenant_ext_id)
    tenant.default_users_group
  end

  def build_user_name(first_name, last_name)
    "#{first_name} #{last_name}"
  end

  def create_manager(employee_id)
    user_infokadry = find_iba_user_by_id(employee_id)
    
    if user_infokadry.nil?
      $asu_log.error("there is no infokadry user with employee_id = #{employee_id}")
      return
    end
    
    email = user_infokadry[EMAIL].downcase

    $asu_log.info("creating manager #{email}")

    user = User.new(userid: email,
                    email:  email,
                    name: build_user_name(user_infokadry[FIRST_NAME], user_infokadry[LAST_NAME]),
                    password: Passgen::generate
    )

    current_group = find_user_group(user_infokadry[DEP_NUMBER])
    user.miq_groups = [current_group]

    begin
      user.save!
    rescue ActiveRecord::RecordInvalid => e
      create_support_ticket("ASU: fail to create manager with id #{employee_id})", e.to_s)
    rescue ActiveRecord::RecordNotUnique => e
      ActiveRecord::Base.connection.reset_pk_sequence!('users')
      user.save!
    end

  end

  def relocate_users
    User.in_my_region.find_each do |user|
      next if admin_user?(user)
      user_infokadry = find_iba_user(user.email)

      if user_infokadry.nil?
        @lost_users.push(user)
      elsif user.current_group.tenant.external_id != user_infokadry[DEP_NUMBER]
        relocate_single_user(user, user_infokadry)
      end

    end
  end

  def admin_user?(user)
    user.email.nil? || user.email.split('@')[1] == 'icdc.io' || user.current_group.try(:group_type) == 'system'
  end

  def relocate_single_user(user, user_infokadry)
    actual_tenant = find_tenant_by_ext_id(user_infokadry[DEP_NUMBER])
    current_tenant = user.current_group.tenant

    $asu_log.info("relocating user #{user.email} from #{current_tenant.description}
                  (#{current_tenant.external_id}) to #{actual_tenant.description} (#{actual_tenant.external_id})")

    if actual_tenant.present?
      correct_group = actual_tenant.default_users_group
      user.miq_groups = [correct_group]
      user.save!

      transfer_services(user, user)
      remove_user_quotas(user)
    else
      $asu_log.info("missing tenant #{user_infokadry[DEP_NUMBER]}")
    end
  end

  def transfer_services(user_from, user_to)
    services = Service.where(evm_owner: user_from)

    actual_group = user_to.current_group
    actual_tenant = actual_group.tenant
    
    send_transfer_service_mail(user_from, user_to, services) if user_from != user_to

    services.each do |service|
      
      if user_from != user_to
        service.update_attribute(:evm_owner, user_to)
        $asu_log.info("service transfer: #{service.name} (#{service.id}) from #{user_from.userid} to #{user_to.userid}")
      end
      
      service.miq_group = actual_group
      service.tenant = actual_tenant
      if service.changed?
        $asu_log.info("updating service #{service.id}")
        log_model_changes("service #{service.id}",service)
        service.save!
      end

      service.vms.each do |vm|
        vm.miq_group = actual_group
        vm.tenant = actual_tenant
        vm.evm_owner = user_to
        vm.save! if vm.changed?
      end

    end
  end

  def delete_lost_users
    @lost_users.each do |lost_user|
      tenant = lost_user.current_group.tenant
      managers = tenant.managers

      transfer_services(lost_user, managers[0]) if managers[0].present?
        
      if Service.where(evm_owner: lost_user).empty?
        $asu_log.info("deleting lost user #{lost_user.userid}")
        lost_user.destroy
      else
        $asu_log.info("fail to delete lost user #{lost_user.userid}, he has not-transferred services")
        
        create_support_ticket("fail to delete lost user #{lost_user.userid}", 
          "Lost user #{lost_user.userid} has not-transferred services")
      end

    end
  end

  def delete_lost_tenants
    tenants = Tenant.in_my_region.where.not(external_id: nil)
    tenants.each do |tenant|
      if find_iba_department(tenant.external_id).nil?
        $asu_log.info("deleting lost tenant #{tenant.description} (#{tenant.external_id})")
        tenant.destroy
      end
    end
  end

  def delete_not_account_users
    User.in_my_region.find_each do |user|
      next if admin_user?(user)

      user_infokadry = find_iba_user(user.email)
      next if user_infokadry.nil?

      if find_tenant_by_ext_id(user_infokadry[DEP_NUMBER]).nil?
        department_infokadry = find_iba_department(user_infokadry[DEP_NUMBER])
        
        log_msg = "deleting not account user #{ user.email } with tree #{ department_infokadry[ANCESTORS] },"\
                  "it leaves services #{Service.where(evm_owner: user).map {|s| s.id}}"
        $asu_log.info(log_msg)

        user.destroy
      end
    end
  end

  def remove_user_quotas(user)
    user.quotas.each { |quota| quota.destroy }
  end

  def generate_tenant_name(external_id)
    "t_#{external_id}"
  end

  def generate_group_name(external_id)
    "g_#{external_id}"
  end

  def find_tenant_by_ext_id(id)
    Tenant.in_my_region.find_by(external_id: id)
  end

  def build_ancestry_with_infocadry(dep)
    ancestry = Tenant.root_tenant.id.to_s
    ancestors = dep[ANCESTORS][0...-1]
    ancestors.each do |ancestor_id|
      ancestor = find_tenant_by_ext_id(ancestor_id)
      ancestry << '/' << ancestor.id.to_s
    end
    ancestry
  end

  def add_tenant(dep)
    external_id = dep[DEP_NUMBER]
    
    args = {
        name:         generate_tenant_name(external_id),
        description:  dep[DEP],
        external_id:  external_id,
        ancestry:     form_tenant_ancestry(dep)
    }

    begin
      Tenant.create!(args)
    rescue ActiveRecord::RecordNotUnique => e
      ActiveRecord::Base.connection.reset_pk_sequence!('tenants')
      ActiveRecord::Base.connection.reset_pk_sequence!('miq_groups')

      Tenant.create!(args)
    end

  end

  def valid_ancestry?(dep)
    return true if dep[ANCESTORS].length == 1
    find_iba_department(dep[ANCESTORS][-2]).nil? ? false : true
  end 

  def form_tenant_ancestry(dep)
    if dep[ANCESTORS].length > 1
      dep_ancestor = find_iba_department(dep[ANCESTORS][-2])
      raise AncestryError if dep_ancestor.nil?

      tenant_ancestor = Tenant.in_my_region.find_by(external_id: dep_ancestor[DEP_NUMBER])
      ancestry = tenant_ancestor.id.to_s
      ancestry = "#{tenant_ancestor.ancestry}/#{ancestry}" if tenant_ancestor.ancestry
      ancestry
    else
      tenant_ancestor = Tenant.root_tenant
      ancestry = tenant_ancestor.id.to_s
    end
  end

  def dep_level(dep)
    dep[ANCESTORS].count - 1
  end

  def date_time_now
    DateTime.now.in_time_zone(MiqServer.my_server.server_timezone)
  end

  def log_start_timestamp
    $asu_log.info("ASU starting at #{date_time_now}, timezone: #{MiqServer.my_server.server_timezone}")
  end

  def log_accounts
    log_msg = "accounts number: #{ @accounts.count },"\
              "accounts ids: #{ @accounts.map{ |a| a.external_id } }"
    $asu_log.info(log_msg)
  end

  def send_transfer_service_mail(user_from, user_to, services)
    subject = "[ICDC.IO] Received services from #{user_from.email}"
    body_template = File.read(Rails.root.join('app/views/asu_mails/transfer_service.html.erb'))
    body = ERB.new(body_template).result(binding)
    
    MiqAeMethodService::MiqAeServiceMethods.send_email(
        user_to.email,
        user_from.email,
        subject,
        body
      )
  end

  def create_support_ticket(title, body)
    begin
      current_user = User.current_user
      User.current_user = nil

      Issue.new_support_issue({
        "name" => title,
        "description" => body,
        "priority" => 1 # low
      })
    ensure
      User.current_user = current_user
    end
  end

  def delete_manager_tags(tenant)
    tenant.destroy_tags(:ns=>"/managed", :cat=>"manager")
  end

  def update_users_emails
    $asu_log.info("updating users emails ...")
    infos = []

    User.in_my_region.find_each do |user|
      next if admin_user?(user)
      user_infokadry = find_iba_user(user.email)


      if user_infokadry.nil? && user.email.include?("iba.by")
        supposed_email = user.email.sub("iba.by", "ibagroup.eu")
        user_infokadry = find_iba_user(supposed_email)
        unless user_infokadry.nil?
          info_msg = "updating user from #{user.email} to #{supposed_email}"
          infos.push(info_msg)
          $asu_log.info(info_msg)
          user.update_attributes(userid: supposed_email, email: supposed_email)
        end
      end

    end

    if infos.present?
      MiqAeMethodService::MiqAeServiceMethods.send_email(
          'support@icdc.io',
          'noreply',
          "users emails rename in #{MiqRegion.my_region.description} location",
          infos.join("<br />")
      )
    end

  end

end
