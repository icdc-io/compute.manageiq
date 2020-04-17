require 'json'

class HaproxyRoute < ActsAsArModel
  def self.show(data)
    data = JSON.parse(data)
    data.empty? ? {} : data
  end
end
