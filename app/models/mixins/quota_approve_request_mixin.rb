module QuotaApproveRequestMixin
  extend ActiveSupport::Concern

  included do
  end
  
  def approve_quota_request?
    source.try(:generic_subtype) == "quota"
  end

  def get_klass_by_account_type
    type = options[:dialog]["dialog_account_type"]
    { "users" => User, "tenants" => Tenant, "groups" => MiqGroup }[type]
  end

  def find_quotable_resource
    klass = get_klass_by_account_type
    klass.find(options[:dialog]["dialog_account_id"])
  end

  def quota_request_test
    dialog = options[:dialog]
    quota_hash = {
        "svm_allocated" => dialog["dialog_svm"],
        "storage_allocated" => dialog["dialog_storage"],
        "hours_allocated" => dialog["dialog_hours"]
    }
    quotable_resource = find_quotable_resource
    quotable_resource.validate_test_quotas(quota_hash)
    quotable_resource.quotas.inject("") do |errors, quota|
      errors << quota.errors.full_messages.join(', ') << ";" if quota.errors.present?
      errors
    end
  end

  def approve_quota_request(userid, reason)
    raise "it is not quota approve request" unless approve_quota_request?
    errors = quota_request_test
    if errors.empty?
      approve(userid, reason)
    else
      raise errors
    end
  end

  module ClassMethods
  end
end
