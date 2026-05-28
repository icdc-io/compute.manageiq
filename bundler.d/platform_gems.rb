if ENV["RAILS_ENV"] == "production" || ENV["RAILS_ENV"] == "test"
  override_gem 'manageiq-schema', git: "https://#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-schema.git", branch: "master"
  override_gem 'manageiq-api', git: "https://#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-api.git", branch: "master"
  override_gem 'manageiq-automation_engine', git: "https://#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-automation_engine.git", branch: "master"
  override_gem 'manageiq-ui-classic', git: "https://#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-ui-classic.git", branch: "master"
  override_gem 'manageiq-providers-ovirt', git: "https://#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-providers-ovirt.git", branch: "master"
  override_gem 'manageiq-decorators', git: "https://#{ENV['GIT_HOST']}/icdc/compute/miq/manageiq-decorators.git", branch: "master"
elsif ENV["RAILS_ENV"] == "development"
  override_gem 'manageiq-schema', :path => File.expand_path('/opt/manageiq/manageiq-schema')
  override_gem 'manageiq-api', :path => File.expand_path('/opt/manageiq/manageiq-api')
  override_gem 'manageiq-automation_engine', :path => File.expand_path('/opt/manageiq/manageiq-automation_engine')
  override_gem 'manageiq-ui-classic', :path => File.expand_path('/opt/manageiq/manageiq-ui-classic')
  override_gem 'manageiq-providers-ovirt', :path => File.expand_path('/opt/manageiq/manageiq-providers-ovirt')
  override_gem 'manageiq-decorators', :path => File.expand_path('/opt/manageiq/manageiq-decorators')
  override_gem 'manageiq-messaging', :path => File.expand_path('/opt/manageiq/manageiq-messaging')
  #gem 'pry'
  #gem 'pry-remote'
  #gem 'pry-nav'
end
