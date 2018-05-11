require 'bundler/setup'
require 'active_resource' unless defined?(ActiveResource)
require 'net/http'
require 'json'
require 'base64'

module RedmineConfig
  REDMINE_CONFIG = YAML.load_file('config/redmine_config.yaml')
end

class IssueFormat
  include Vmdb::Logging
  include ActiveResource::Formats::XmlFormat

  def encode(hash, options = {})
    hash.to_xml(options)
  end

  def decode(xml)
    data = from_xml_data(Hash.from_xml(xml))
    if data.kind_of?(Array)
      data.each do |issue|
        next unless issue["category"]
        issue["redmine_category"] = issue["category"]
        issue.delete("category")
      end
    elsif data["category"]
      data["redmine_category"] = data["category"]
      data.delete("category")
    end
    data
  end

  def from_xml_data(data)
    if data.kind_of?(Hash) && data.keys.size == 1
      data.values.first
    else
      data
    end
  end
end

class Users < ActiveResource::Base
  include Vmdb::Logging
  self.include_root_in_json = true
  self.site = RedmineConfig::REDMINE_CONFIG[:project_url]
  self.user = RedmineConfig::REDMINE_CONFIG[:user]
  def self.headers
    new_headers = {}
    new_headers["X-Redmine-API-Key"] = RedmineConfig::REDMINE_CONFIG[:api_key]
    new_headers
  end
  self.format = ActiveResource::Formats::XmlFormat #::JsonFormatter.new(:issues)
end

class IssueStatus < ActiveResource::Base
  include Vmdb::Logging
  self.include_root_in_json = true
  self.site = RedmineConfig::REDMINE_CONFIG[:project_url]
  self.user = RedmineConfig::REDMINE_CONFIG[:user]
  self.format = ActiveResource::Formats::XmlFormat
  def self.headers
    new_headers = {}
    new_headers["X-Redmine-API-Key"] = RedmineConfig::REDMINE_CONFIG[:api_key]
    new_headers
  end
end

class CustomField < ActiveResource::Base
  include Vmdb::Logging
  self.include_root_in_json = true
  self.site = RedmineConfig::REDMINE_CONFIG[:project_url]
  self.user = RedmineConfig::REDMINE_CONFIG[:user]
  self.format = ActiveResource::Formats::XmlFormat
  def self.headers
    new_headers = {}
    new_headers["X-Redmine-API-Key"] = RedmineConfig::REDMINE_CONFIG[:api_key]
    new_headers
  end
end

class Issue < ActiveResource::Base
  include Vmdb::Logging
  self.include_root_in_json = true
  self.site = RedmineConfig::REDMINE_CONFIG[:project_url]
  self.user = RedmineConfig::REDMINE_CONFIG[:user]
  self.format = IssueFormat.new # ::JsonFormatter.new(:issues)
  def self.headers
    new_headers = {}
    new_headers["X-Redmine-API-Key"] = RedmineConfig::REDMINE_CONFIG[:api_key]
    new_headers["X-Redmine-Switch-User"] = User.current_user.email if User.current_user.present?
    new_headers
  end

  def self.columns_hash
    {}
  end

  def self.count
  end

  def keys
  end

  def close
    # self.status_id =  self.class.get_close_status.id
    self.status.id == '7' ? self.status_id = '12' : self.status_id = '11'
    save
  end

  # def self.get_close_status
  #   IssueStatus.all.find { |status| status.is_closed == "true" }
  # end

  def [](attr)
    @attributes[attr.to_s]
  end

  alias_method :read_attribute, :[]

  def self.new_support_issue(data)
    uploads = Issue.upload_files(data["files"])

    issue = Issue.new(
      :subject     => data["name"],
      :project_id  => RedmineConfig::REDMINE_CONFIG[:project_id], # main project 'public' (id=5)
      :tracker_id  => RedmineConfig::REDMINE_CONFIG[:tracker_id], # error (id=1)
      :description => data["description"],
      :priority_id => data["priority"],
      :uploads     => uploads,
    )

    custom_fields = {}
    custom_fields["Service"] = data["service_id"] if data["service_id"]
    custom_fields["Tenant"] = User.current_user.present? ? User.current_user.current_tenant.name : ""
    issue.set_custom_fields(custom_fields)
    issue.save
    self.format_issue(issue)
  end

  def add_comment(text, files)
    uploads = Issue.upload_files(files)
    self.notes = text
    self.uploads = uploads
    switch_state
    save
  end

  def set_custom_fields(data)
    self.custom_fields = []
    field_names = data.keys
    fields = CustomField.all.select { |field| field_names.include?(field.name) }
    fields.each do |field|
      self.custom_fields.push({ "id" => field.id, "value" => data[field.name] })
    end
  end

  def self.find_issue(id, format = true)
    user = Users.find(:all, :params => { :name => User.current_user.email})[0]
    issue = self.find(id, :params => { :include => "journals,attachments"})
    issue = self.format_issue(issue, user.id) if format
    issue
  end

  def self.find_service_issues(id)
    issues = self.find(:all, :params => { :project_id => RedmineConfig::REDMINE_CONFIG[:project_id], :cf_5 => id, :status_id => '*' })

    issues.each do |issue|
      self.format_issue(issue)
    end

    issues
  end

  def self.find_user_issues
    user = Users.find(:all, :params => { :name => User.current_user.email})[0]

    return {} unless user

    issues = self.find(:all, :params => { :author_id => user.id, :project_id => RedmineConfig::REDMINE_CONFIG[:project_id], :status_id => '*' })

    issues.each do |issue|
      self.format_issue(issue)
    end

    issues
  end

  def self.get_status(status)
    statusMap = RedmineConfig::REDMINE_CONFIG[:status_name]
    statusMap[status]
  end

  def self.get_priority(priority)
    priorityMap = RedmineConfig::REDMINE_CONFIG[:priority]
    priorityMap[priority]
  end

  def self.format_issue(issue, user_id = nil)
    issue.uploads = issue.try(:uploads)&.map(&:filename)
    issue.attachments = issue.try(:attachments)&.map(&:filename)
    issue.project = issue.project.name
    issue.tracker = issue.tracker.name
    issue.stat_id = issue.status.id.to_i
    issue.status = get_status(issue.status.id.to_i)
    issue.author = issue.author.name
    begin
      issue.assigned_to = issue.assigned_to.name
    rescue NoMethodError
      issue.assigned_to = ""
    end
    issue.fixed_version = ""
    issue.custom_fields = ""
    issue.priority = get_priority(issue.priority.id.to_i)
    issue.parent = ""
    begin
      issue.redmine_category = issue.redmine_category.name
    rescue NoMethodError
      issue.redmine_category = ""
    end
    if user_id
      details = []
      issue.journals.each do |journal|
        next unless journal.notes
        note = {"created_on" => journal.created_on, "note" => journal.notes.encode("UTF-8")}
        note["user"] = journal.user.id == user_id ? "_Me" : journal.user.name
        note['uploads'] = []
        journal.details.each { |d| note['uploads'] << d.new_value if d.property == 'attachment' }
        issue.attachments.pop(note['uploads'].size)
        details.push(note)
      end
      issue.journals = details
    end
    issue
  end

  def self.upload_files(files)
    return [] if files.nil? || files.empty?

    uri = URI(RedmineConfig::REDMINE_CONFIG[:project_url])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Post.new('/uploads.json')

    req.content_type = "application/octet-stream"
    req['X-Redmine-API-Key'] = RedmineConfig::REDMINE_CONFIG[:api_key]

    uploads = []

    files.each do |file|
      req.body = Base64.decode64(file["base64"])

      response = http.request(req)

      upload = JSON.parse(response.body)

      uploads << {
        :token        => upload["upload"]["token"],
        :filename     => file["filename"],
        :content_type => "image/*",
      }
    end

    uploads
  end

  private

  def switch_state
    status_map = RedmineConfig::REDMINE_CONFIG[:status_map]
    ids_bunch = status_map.map { |_, transit| [transit[:from], transit[:to]] }
    ids_from, ids_to = ids_bunch.transpose
    id = status.id.to_i

    if ids_from.include? id
      ind = ids_from.index(id)
      self.status_id = ids_to[ind]
    end
  end

end
