module IcdcServiceMixin
  extend ActiveSupport::Concern

  included do
    extend InterRegionApiMethodRelay
    api_relay_method :share do |options|
      options
    end
  end

  def share(data)
    _log.info("OBEKASOV share")
  end
end
