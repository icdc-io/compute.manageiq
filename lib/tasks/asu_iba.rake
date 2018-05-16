namespace :asu do

  desc "update iba account structure"
  task :update => :environment do
    AccountStructure::AccountStructureUpdaterIBA.new.update_structure
  end

  desc "update user emails from iba.by to ibagroup.eu"
  task :update_users_emails => :environment do
    AccountStructure::AccountStructureUpdaterIBA.new.update_users_emails
  end

end
