module IcdcServiceMixin
  extend ActiveSupport::Concern

  included do
    extend InterRegionApiMethodRelay
    api_relay_method :share do |options|
      options
    end

    api_relay_method :usnhare do |options|
      options
    end
  end

  def share(data)
    project_tag = data['existed_project']

    users_ids = data['added_users']

    if project_tag.blank?
      _log.info("OBEKASOV share CREATING TAG")
      project_tag = (0...3).map { ('a'..'z').to_a[rand(26)] }.join.downcase + evm_owner_id.to_s
      Classification.find_by(:name => 'project').add_entry(:name => project_tag, :description => project_tag)
    end

    tag_add(project_tag, :ns => '/managed', :cat => 'project')

    _log.debug("OBEKASOV share project_tag #{project_tag}")
    _log.debug("OBEKASOV share users_ids #{users_ids}")

    users_ids.each do |id|
      user = User.find_by(:userid => id)
      user.tag_add(project_tag, :ns => '/managed', :cat => 'project')

      # send = {}
      # send['name'] = u.name
      # send['email'] = user
      # $evm.set_state_var(:send, send)
      # $evm.instantiate("/Service/Email/Email/SharingService") unless  $evm.root['user'].userid == user
    end

    vms.each do |vm|
      vm.tag_add(project_tag, :ns => '/managed', :cat => 'project')
    end
  end

  def unshare(data)
  end
end
