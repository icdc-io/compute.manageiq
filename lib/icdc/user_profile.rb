module Icdc
  class UserProfile
    def self.user_profile
      {:user_info => user_info, :ssh_keys => ssh_keys, :projects_roles => projects_roles}
    end

    def self.user_info
      name = User.current_user.name.empty? ? User.current_user.email : User.current_user.name
      {:name => name, :email => User.current_user.email, :last_activity => User.current_user.updated_on.strftime("%d.%m.%Y")}
    end

    def self.ssh_keys
      User.current_user.available_keys
    end

    def self.delete_key(id)
      raise ForbiddenError, "Cannot delete alien ssh key!" unless GenericObject.find(id).user.first.email == User.current_user.email

      GenericObject.find(id).destroy!
    end

    def self.create_or_modify(data)
      update = true
      update = false if data["resource"]["id"].nil?
      if update
        modify_key(data)
      else
        add_key(data)
      end
    end

    def self.add_key(data)
      go = GenericObjectDefinition.find_by(:name => "SshKey").create_object(:name => data["resource"]["name"], :key => data["resource"]["key"])
      go.user = [User.current_user]
      go.save!
    end

    def self.modify_key(data)
      go = GenericObject.find_by(:id => data["resource"]["id"])
      go.name = data["resource"]["name"] if data["resource"]["name"].present?
      go["properties"]["key"] = data["resource"]["key"] if data["resource"]["key"].present?
      go.save!
    end

    def self.projects_roles
      gen_result = []
      User.current_user.tenants.collect(&:name).each do |tenant_name|
        User.current_user.miq_groups.where("description LIKE?", "#{tenant_name}%").each do |r|
          role = r.description.split(".").second
          result = { :project => tenant_name, :role => role }
          gen_result.push(result)
        end
      end
      gen_result
    end
  end
end
