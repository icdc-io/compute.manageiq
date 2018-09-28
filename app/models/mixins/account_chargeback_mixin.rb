module AccountChargebackMixin
  extend ActiveSupport::Concern

  def group_bydate_and_sum(chbs)
    grouped_chbs = chbs.group_by { |chb| chb["start_date"] }
    summed_costs = grouped_chbs.map do |start_date, gr_chbs|
      sum = 0
      gr_chbs.each do|chb|
      sum += chb["cost"]
      _log.info("DBG chargeback #{chb}")
      end
      {"start_date"=>start_date, "cost"=>sum}
    end
    summed_costs
  end

  def combine_chargebacks(costs, another_costs)
    group_bydate_and_sum(costs + another_costs)
  end
end
