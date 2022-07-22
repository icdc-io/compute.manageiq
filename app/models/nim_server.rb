#require 'hmc/sdk'
class NimServer < PxeServer
  virtual_has_one :ems

  def ems
    ExtManagementSystem.find_by(:guid => uri)
  end

  def sync_pxe_images
    connection_nim = ems.connect_nim
    connection_nim.sync_resources.each do |resource|
      image_hash = {}
      connection_nim.describe_resource_object(:resource_name => resource).each_value do |value|
        value.each_value do |i_key|
          next if %w[res_group groups].include?(i_key)

          image_hash.merge!(connection_nim.describe_resource_object(:resource_name => i_key)[i_key])
        end
      end
      PxeImage.create!(:name => resource, :description => resource, :pxe_server_id => id, :type => nil, :kernel => image_hash["os_level_r"], :path => image_hash["location"]) unless PxeImage.find_by(:name => resource)
    end
    update!(:last_refresh_on => Time.now.utc)
  end
end
