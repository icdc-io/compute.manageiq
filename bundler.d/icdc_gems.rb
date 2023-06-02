if ENV["RAILS_ENV"] == "production" || ENV["RAILS_ENV"] == "test"
=begin ahrechushkin JUST FOR TESTS
  override_gem 'manageiq-schema', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-schema.git", branch: "icdc_j"
  override_gem 'manageiq-api', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-api.git", branch: "icdc_j"
  override_gem 'manageiq-automation_engine', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-automation_engine.git", branch: "icdc_j"
  override_gem 'manageiq-ui-classic', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-ui-classic.git", branch: "icdc_j"
  override_gem 'manageiq-providers-ovirt', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-providers-ovirt.git", branch: "icdc_j"
=end
#  override_gem 'manageiq-providers-power_systems', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-providers-power_systems.git", branch: "icdc_j"
#  override_gem 'hmc-sdk-ruby', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/hmc-sdk-ruby.git", branch: "icdc_j"
  #override_gem 'manageiq-decorators', git: "https://#{ENV['GIT_AUTH']}@#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-decorators.git", branch: "icdc_j"


  override_gem 'manageiq-schema', git: "https://code.zby.scdc.io/icdc/compute/miq/manageiq-schema.git", branch: "icdc_j"
  override_gem 'manageiq-api', git: "https://code.zby.scdc.io/icdc/compute/miq/manageiq-api.git", branch: "icdc_j"
  override_gem 'manageiq-automation_engine', git: "https://code.zby.scdc.io/icdc/compute/miq/manageiq-automation_engine.git", branch: "icdc_j"
  override_gem 'manageiq-ui-classic', git: "https://code.zby.scdc.io/icdc/compute/miq/manageiq-ui-classic.git", branch: "icdc_j"
  override_gem 'manageiq-providers-ovirt', git: "https://code.zby.scdc.io/icdc/compute/miq/manageiq-providers-ovirt.git", branch: "icdc_j"
  override_gem 'manageiq-decorators', git: "https://code.zby.scdc.io/icdc/compute/miq/manageiq-decorators.git", branch: "icdc_j"
elsif ENV["RAILS_ENV"] == "development"
  override_gem 'manageiq-schema', :path => File.expand_path('/opt/manageiq/manageiq-schema')
  override_gem 'manageiq-api', :path => File.expand_path('/opt/manageiq/manageiq-api')
  override_gem 'manageiq-automation_engine', :path => File.expand_path('/opt/manageiq/manageiq-automation_engine')
  override_gem 'manageiq-ui-classic', :path => File.expand_path('/opt/manageiq/manageiq-ui-classic')
  override_gem 'manageiq-providers-ovirt', :path => File.expand_path('/opt/manageiq/manageiq-providers-ovirt')
#  override_gem 'manageiq-providers-power_systems', :path => File.expand_path('/opt/manageiq/manageiq-providers-power_systems')
#  override_gem 'hmc-sdk-ruby', :path => File.expand_path('/opt/manageiq/hmc-sdk-ruby')
  override_gem 'manageiq-decorators', :path => File.expand_path('/opt/manageiq/manageiq-decorators')
  override_gem 'manageiq-messaging', :path => File.expand_path('/opt/manageiq/manageiq-messaging')
  #gem 'pry'
  #gem 'pry-remote'
  #gem 'pry-nav'
end
