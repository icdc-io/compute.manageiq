class MiqUiWorker::Runner < MiqWorker::Runner
  include MiqWebServerRunnerMixin

  def prepare
    super
    update_region_info
    MiqApache::Control.start if MiqEnvironment::Command.is_podified?
  end

  def update_region_info
    content = ERB.new(File.new('config/locations.js.erb').read).result(binding)
    File.open('public/ui/service/js/locations.js', 'w') { |f| f.write content }
  end
end
