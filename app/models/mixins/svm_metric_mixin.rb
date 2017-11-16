module SvmMetricMixin
  extend ActiveSupport::Concern
  included do
    has_many :svm_metrics
    has_many :svm_metric_rollups
  end


  SVM_METRIC_ROLLUP_MODELS = %(Vm User MiqGroup Tenant).freeze
  def svmh_used
    raise _("SvmMetricRollup does not support such model") unless SVM_METRIC_ROLLUP_MODELS.include?(self.class.name)
    rollup_query="#{self.class.name.underscore}_id = ?"
    svmh = SvmMetricRollup.where(rollup_query, id).sum(:svmh)
    svmh = 0.0 if svmh.nil?
    svmh
  end

end
