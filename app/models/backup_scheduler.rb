class BackupScheduler < ApplicationRecord

  def self.create(data)
    schedule = self.new
    schedule.name = data['name'] || "#{data['resource_id']} backup"
    schedule.backup_type = data['type'] || 'service'
    schedule.resource_id = data['resource_id']
    schedule.cron_m = data['cron_m'] || '*'
    schedule.cron_h = data['cron_h'] || '*'
    schedule.cron_dom = data['cron_dom'] || '*'
    schedule.cron_mon = data['cron_mon'] || '*'
    schedule.cron_dow = data['cron_dow'] || '*'
    schedule.save!
    cron_cmd = "#{schedule.cron_m} #{schedule.cron_h} #{schedule.cron_dom} #{schedule.cron_mon} #{schedule.cron_dow} root /var/www/miq/vmdb/scripts/backup.sh #{schedule.resource_id}"
    File.open("/etc/cron.d/#{schedule.id}", 'w') {|file| file.write(cron_cmd)}
    schedule

  end

  def edit(data)
    self.name = data['name'] if data['name']
    self.cron_m = data['cron_m'] if data['cron_m']
    self.cron_h = data['cron_h'] if data['cron_h']
    self.cron_dom = data['cron_dom'] if data['cron_dom']
    self.cron_mon = data['cron_mon'] if data['cron_mon']
    self.cron_dow = data['cron_dow'] if data['cron_dow']
    self.save!
    cron_cmd = "#{self.cron_m} #{self.cron_h} #{self.cron_dom} #{self.cron_mon} #{self.cron_dow} root /var/www/miq/vmdb/scripts/backup.sh #{self.resource_id}"
    File.open("/etc/cron.d/#{self.id}", 'w') {|file| file.write(cron_cmd)}
    self
  end

  def delete
    File.delete("/etc/cron.d/#{self.id}") if File.exist?("/etc/cron.d/#{self.id}")
    self.destroy
  end

end
