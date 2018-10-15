module AccountChargebackMixin
  extend ActiveSupport::Concern

  def group_bydate_and_sum(chbs)
    grouped_chbs = chbs.group_by { |chb| chb[:start_date] }
    #_log.info("DBG api grouped chbs #{chbs}")
    summed_costs = grouped_chbs.map do |start_date, gr_chbs|
      sum = 0
      gr_chbs.each do|chb|
      sum += chb[:cost] || 0 
      end
      {"start_date"=>start_date, "cost"=>sum}
    end
    summed_costs
  end

  def combine_chargebacks(costs, another_costs)
    group_bydate_and_sum(costs + another_costs)
  end
end
