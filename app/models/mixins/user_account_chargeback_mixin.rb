module UserAccountChargebackMixin
  extend ActiveSupport::Concern

  def find_services_by_owner
    Service.where(evm_owner: self)
  end

  def services_chargebacks(period)
    services = find_services_by_owner
    costs = services.flat_map { |service| service.total_costs_bydate(period) }
    group_bydate_and_sum(costs)
  end

  def services_chargebacks_monthly
    services = find_services_by_owner
    costs = services.flat_map { |service| service.total_costs_bydate }
    group_bydate_and_sum(costs)
  end

end
