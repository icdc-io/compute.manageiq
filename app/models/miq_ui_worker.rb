class MiqUiWorker < MiqWorker
  require_nested :Runner

  self.required_roles = ['user_interface']
  self.check_for_minimal_role = false
  self.workers = lambda do
    if MiqServer.minimal_env?
      # Force 1 UI worker in minimal mode, unless 'no_ui' is an option, which is
      # done when the UI worker is debugged externally, such as in Netbeans.
      MiqServer.minimal_env_options.include?("no_ui") ? 0 : 1
    else
      worker_settings[:count]
    end
  end

  STARTING_PORT = 3000

  def friendly_name
    @friendly_name ||= "User Interface Worker"
  end

  include MiqWebServerWorkerMixin
  include MiqWorker::ServiceWorker

  def self.supports_container?
    true
  end

  def self.bundler_groups
    %w[manageiq_default ui_dependencies graphql_api]
  end

  def self.kill_priority
    MiqWorkerType::KILL_PRIORITY_UI_WORKERS
  end

  def container_port
    3001
  end

  def container_image_name
    (ENV["CONTAINER_IMAGE_PRODUCT"] || "manageiq") + "-ui-worker" + (ENV["DEV_ENVIRONMENT"] || '')
  end

  def mount_configmap(container_definition)
    return unless ENV['CUSTOM_CONFIG_NAME']
    container_definition[:spec][:template][:spec][:volumes][:configMap].merge!({:default_mode => 420, :name => 'httpd-configs-ui-worker'})
    container_definition[:spec][:template][:spec][:containers].first.merge!({:volumeMounts => [{ :mountPath => '/etc/httpd/conf', :name => 'httpd-configs-ui-worker', :readOnly => true }]})
    container_definition
  end
end
