module IcdcServiceScheduleMixin
  extend ActiveSupport::Concern

  BACKUP_RETENTION_NAME = "backup_retention_period"
  DEFAULT_BACKUP_RETENTION_PERIOD = 'week'

  included do
    extend InterRegionApiMethodRelay

    has_many :miq_schedules, as: :schedulable, dependent: :destroy

    api_relay_method :schedule_power_op do |options|
      options
    end

    api_relay_method :schedule_backup do |options|
      options
    end
  end

  def schedule_power_op(params)
    miq_schedules.create(
      :name         => "service #{name} power #{params["power"]} scheduled at #{params["start_time"]}",
      :description  => "power #{params["power"]}",
      :sched_action => { :method => "service_power_op", :options => params.slice("power") },
      :filter       => MiqExpression.new("=" => {"field" => "Service-id", "value" => id}),
      :towhat       => self.class.name,
      :run_at       => { :interval => {unit: params['interval_unit'], value: '1'}, :start_time => params['start_time'] },
      :prod_default => "system"
    )
  end

  def incorrect_term?(term)
    has_monthly_schedules = self.miq_schedules.any? do |schedule|
      int_unit = schedule[:run_at][:interval][:unit]
      int_unit.present? ? int_unit == "monthly" : false
    end

    has_monthly_schedules && ["week", "month"].include?(term)
  end

  def schedule_backup(params)
    miq_schedules.create(
      :name         => "service #{name} backup scheduled at #{params["start_time"]}",
      :description  => "backup",
      :sched_action => { :method => "service_backup", :options => {} },
      :filter       => MiqExpression.new("=" => {"field" => "Service-id", "value" => id}),
      :towhat       => self.class.name,
      :run_at       => { :interval => { :unit => params['interval_unit'], :value => '1' }, :start_time => params['start_time'] },
      :prod_default => "system"
    )

    backup_retention_period = "quarter" if incorrect_term?(backup_retention_period)
  end

  def backup_retention_period
    @backup_retention_period ||= backup_retention_attr&.value || DEFAULT_BACKUP_RETENTION_PERIOD
  end

  def backup_retention_period=(value)
    attr = backup_retention_attr || create_default_backup_retention_period

    if incorrect_term?(value)
      raise ArgumentError, %q{Unsuitable [Delete older than] value.
                               You may set [Delete older than] greater than month period,
                               because you have a month scheduler.}
    end

    attr.update!(:value => value)
  end

  def backup_retention_attr
    @backup_retention_attr ||= custom_attributes.find_by(:name => BACKUP_RETENTION_NAME)
  end

  def create_default_backup_retention_period
    custom_attributes.create(:name => BACKUP_RETENTION_NAME, :value => DEFAULT_BACKUP_RETENTION_PERIOD)
  end

  def retention_period_to_duration
    case backup_retention_period
    when "week"    then 1.week
    when "month"   then 1.month
    when "quarter" then 3.months
    when "year"    then 1.year
    end
  end

  def outdated_backup?(backup)
    backup_created_at = DateTime.parse(backup[:serialized_value]["end_date"])
    delete_at = backup_created_at + retention_period_to_duration
    delete_at < self.class.time_now
  end

  def outdated_backups
    backups.select { |backup| outdated_backup?(backup) }
  end

  module ClassMethods
    def delete_outdated_backups
      find_each do |backupable|
        backupable.outdated_backups.each do |backup|
          begin
            backupable.invoke_custom_action('delete_backup', User.admin, {'backup_name' => backup.name })
          rescue
          end
        end
      end
    end

    def time_now
      Time.now.in_time_zone(MiqServer.my_server.server_timezone)
    end
  end
end
