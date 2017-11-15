require 'json'

class HaproxyRoute < ActsAsArModel
  def self.show(data)
    data = JSON.parse(data) 
    return data
  end

end
