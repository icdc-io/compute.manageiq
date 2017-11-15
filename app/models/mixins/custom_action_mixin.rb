module CustomActionMixin
  extend ActiveSupport::Concern

  included do
  end

  def find_custom_action_button(action)
    custom_action_buttons.find { |b| b.name.downcase == action.downcase }
  end

  def custom_action_with_dialog?(custom_button)
    custom_button.resource_action.dialog_id.present?
  end

  def submit_custom_action_dialog(custom_button, user, data)
    wf = ResourceActionWorkflow.new({}, user, custom_button.resource_action, :target => self)
    data.each { |key, value| wf.set_value(key, value) } if data.present?
    wf_result = wf.submit_request
    raise StandardError, Array(wf_result[:errors]).join(", ") if wf_result[:errors].present?
    wf_result
  end

  def invoke_custom_action(action, user = nil, data = nil)
    custom_button = find_custom_action_button(action)

    if custom_action_with_dialog?(custom_button)
      return submit_custom_action_dialog(custom_button, user, data)
    end

    custom_button.invoke(self)
  end

  module ClassMethods
  end
end
