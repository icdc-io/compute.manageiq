module IcdcServiceMixin
  extend ActiveSupport::Concern

  included do
    extend InterRegionApiMethodRelay

    virtual_column :domains,      :type => :string
    virtual_column :shared_users, :type => :string

    api_relay_method :share do |options|
      options
    end

    api_relay_method :unshare do |options|
      options
    end
  end

  def share(data)
    project_tag = find_project_tag

    userids = data['userids']

    if project_tag.blank?
      project_tag = (0...3).map { ('a'..'z').to_a[rand(26)] }.join.downcase + evm_owner_id.to_s
      Classification.find_by_name('project').add_entry(:name => project_tag, :description => project_tag)
    end

    tag_add(project_tag, :ns => '/managed', :cat => 'project')

    userids.each do |userid|
      user = User.find_by(:userid => userid)
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
    userid = data['userid']
    user = User.find_by_userid(userid)
    project_tag = find_project_tag
    Classification.unclassify_by_tag(user, project_tag)
  end

  def shared_users
    project_tag = find_project_tag

    if project_tag
      project_name = project_tag.split('/')[-1]
      User.find_tagged_with(:any => project_name, :ns => '/managed/project')
    else
      []
    end
  end

  def domains
    Classification.where(parent_id: Classification.find_by_name('domain', region_number)&.id).map(&:description)
  end

  private

  def find_project_tag
    tags(:ns => "/managed/project/").first&.name
  end
end
