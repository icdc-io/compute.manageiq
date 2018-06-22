class ComplianceReport < ActiveResource::Base
  include Vmdb::Logging
  self.include_format_in_path = false
  self.site = "http://compliance-server.icdc.io:9080/HChecker-DPC/api"
  self.format = ActiveResource::Formats::XmlFormat
  self.set_collection_name 'report'

  def self.columns_hash
    {}
  end

  def self.count
  end

  def self.length
  end

  def keys
  end

  def [](attr)
    @attributes[attr.to_s]
  end

  def self.get_service_reports(service)
    reports = []
    service.vms.each do |vm|
      begin
        report = self.find(vm.id)
        report = JSON.parse(report.server.to_json)
        format_report(report)
      rescue => err
        report = {'status' => 'No Information', 'error_message' => err.message, 'id' => vm.id }
      end
      report['vm_name'] = vm.name
      reports << report
    end
    reports
  end

  def self.format_report(report)
    report["application"] = [report["application"]] unless report["application"].kind_of?(Array)
    report["status"] = "Non Compliant" if report["status"]=="NonCompliant"
    report["application"].each do |app|
      app["status"] = "Non Compliant" if app["status"]=="NonCompliant"
    end
  end

  def self.update_reports(policies)
    answer = {'success' => true}
    policies.each do |policy|
        server_id = policy['id']
        policy_name = policy['name']
        url = (site + collection_path + "hc/run/#{server_id}/#{policy_name}").to_s
        begin
          response = RestClient.post(url, '',{content_type: :json, accept: :json})
        rescue RestClient::ExceptionWithResponse => err
          answer['success'] = false;
          answer['error_message'] = err.response
        end
    end
    answer
  end

end
