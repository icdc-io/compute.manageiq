module IcdcUserMixin
  extend ActiveSupport::Concern

  # rubocop:disable Naming/AccessorMethodName, Lint/MissingCopEnableDirective

  included do
    virtual_attribute :ssh_keys, :string
  end

  def ssh_keys
    {:ssh_keys => available_keys}
  end

  def available_keys
    result = []
    GenericObject.all.select { |go| go.generic_object_definition_name == "SshKey" }.select { |go| go.user.first }.select { |go| go.user.first.email == email }.map do |go|
      template = { :name => go.name, :key => go["properties"]["key"], :id => go.id }
      result.push(template)
    end
    result
  end

end
