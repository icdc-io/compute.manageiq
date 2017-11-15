class Quota < ApplicationRecord
  self.abstract_class = true
  include QuotaMixin
end