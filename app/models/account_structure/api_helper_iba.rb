module AccountStructure::ApiHelperIBA
  extend ActiveSupport::Concern

  included do
  end

  DEP_NUMBER = "DepartNumber"
  CHIEF_ID = "ChiefId"
  EMPLOYEE_ID = "EmployeeID"
  EMAIL = "e_mail"
  DEP = "Otdele"
  ANCESTORS = "DepartUN"
  FIRST_NAME = "FirstName_eng"
  LAST_NAME = "LastName_eng"

  def find_iba_user(email)
    return nil if email.nil?

    req = Net::HTTP::Get.new("/users/search?key=e_mail&value=#{email}&access_token=#{get_rest_service_token}")
    call_iba_rest_service(req)[0]
  end

  def find_iba_user_by_id(id)
    req = Net::HTTP::Get.new("/users/search?key=EmployeeID&value=#{id}&access_token=#{get_rest_service_token}")
    response  = call_iba_rest_service(req)
    for person in response
      return person if person["EmployeeID"] == id
    end
    nil
  end

  def find_iba_department(id)
    req = Net::HTTP::Get.new("/departments/search?key=DepartNumber&value=#{id}&access_token=#{get_rest_service_token}")
    call_iba_rest_service(req)[0]
  end

  def find_group_users(id)
    req = Net::HTTP::Get.new("/users/search?key=DepartNumber&value=#{id}&access_token=#{get_rest_service_token}")
    call_iba_rest_service(req)[0]
  end

  def dep_subtree_list(level, id)
    req = Net::HTTP::Get.new("/departments/search?key=DepartLevel#{level}&value=#{id}&access_token=#{get_rest_service_token}")
    call_iba_rest_service(req)
  end

  def departments_tree
    req = Net::HTTP::Get.new("/departments/tree?access_token=#{get_rest_service_token}")
    call_iba_rest_service(req)
  end


  def call_iba_rest_service(req)
    http = Net::HTTP.new(iba_rest_service_config['host'], iba_rest_service_config['port'])
    JSON.parse(http.request(req).body)
  end

  def iba_rest_service_config
    @config ||= YAML.load_file(File.join(Rails.root, "config/iba_rest_service.yaml"))
  end

  def get_rest_service_token
    iba_rest_service_config['token']
  end

  module ClassMethods
  end

end

