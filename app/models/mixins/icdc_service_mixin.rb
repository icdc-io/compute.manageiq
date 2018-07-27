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
    project_tag = find_project_tag || create_porject_tag

    userids = data['userids']

    Classification.classify(self, 'project', project_tag)

    userids.each do |userid|
      user = User.find_by(:userid => userid)
      Classification.classify(user, 'project', project_tag)

      # TODO: email user
    end

    vms.each { |vm| Classification.classify(vm, 'project', project_tag) }
  end

  def unshare(data)
    userid = data['userid']
    user = User.find_by_userid(userid)
    project_tag = find_project_tag
    Classification.unclassify(user, 'project', project_tag)
  end

  def shared_users
    project_tag = find_project_tag

    project_tag ? User.find_tagged_with(:any => project_tag, :ns => '/managed/project') : []
  end

  def domains
    Classification.where(parent_id: Classification.find_by_name('domain', region_number)&.id).map(&:description)
  end

  private

  def find_project_tag
    tags(:ns => "/managed/project/").first&.classification&.name
  end

  def create_porject_tag
    tag = (0...3).map { ('a'..'z').to_a[rand(26)] }.join.downcase + evm_owner_id.to_s
    Classification.find_by_name('project').add_entry(:name => tag, :description => tag).name
  end
end
