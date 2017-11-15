class SvmMetricRollup < ApplicationRecord
  belongs_to :vm
  belongs_to :user
  belongs_to :miq_group
  belongs_to :tenant

  def self.store
    $api_log.info("String rolling up svm metrics")
    m_prev = {} #store last metric svm for each vm
    svm_hours = {} #accumulated svm_hours values
    SvmMetric.where('ts >= ?', 30.days.ago).order(ts: :asc).each do |m|
      mkey = "#{m.vm_id},#{m.user_id},#{m.miq_group_id},#{m.tenant_id}"
      mp = m_prev[mkey]
      unless mp.nil?
        svm_avg = (mp.svm + m.svm) / 2.0
        hours = (m.ts - mp.ts) / 3600.0
        svm_hours[mkey] += svm_avg * hours
      else
        svm_hours[mkey] = 0.0
      end
      m_prev[mkey] = m
    end
    svm_hours.each do |mkey, svmh|
      $api_log.info("[DBG] Store mkey:#{mkey.inspect}, svmh:#{svmh}")
      key = mkey.split(",").map{ |k| (k.empty? ? nil : k.to_i) }
      r = SvmMetricRollup.find_or_initialize_by(
                     vm_id: key[0],
                     user_id: key[1],
                     miq_group_id: key[2],
                     tenant_id: key[3])
      r.svmh = svmh
      r.ts = Time.new
      begin
        r.save
      rescue => err
       _log.error("Failed to store SvmMetricRollup [#{mkey}]: #{err}")
      end
    end
    SvmMetricRollup.where('ts < ?', 30.days.ago).each do |m|
      m.destroy
    end
    _log.info("Rolled up all SvmMetrics")
  end

end
