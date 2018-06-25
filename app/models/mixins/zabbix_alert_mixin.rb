require 'zabbixapi'

module ZabbixConfig
  ZCFG = YAML.load_file(Rails.root.join("config","zabbix.yml"))
end

module ZabbixAlertMixin
  extend ActiveSupport::Concern

  def get_triggers
    data = get_triggers_from_host
    data_new = create_frontend_data(data)
    data_new
  end

  def enabled_resource
    data = get_triggers_from_host
    {"enabled" => data.first["status"]}
  end

  def delete_triggers(data)
    items = connection.query(:method => "item.get", :params => {:triggerids => "#{data["trigger_id"]}"})
    itemids = items.map! { |item| item["itemid"]}
    connection.query(:method => "trigger.delete", :params => ["#{data["trigger_id"]}"])
    unless itemids.empty?
      connection.query(:method => "item.delete", :params => itemids)
    end
  end

  def disable_triggers
    triggers = get_triggers_from_host
    triggers.each do |trigger|
      connection.query(:method => "trigger.update", :params => {:triggerid => trigger["triggerid"], :status => 1})
    end
    enabled_resource
  end

  def enable_triggers
    triggers = get_triggers_from_host
    triggers.each do |trigger|
       connection.query(:method => "trigger.update", :params => {:triggerid => trigger["triggerid"], :status => 0})
    end
    enabled_resource
  end

  #Main function
  def create_triggers(data)
    #data = data["params"]
    #Need have host to attach triggers
    hosts = connection.query(:method => "host.get",:params => {:output => ["host"],:selectInventory => ["alias"], :searchInventory => {:alias => "#{id}" }})
    if hosts.empty?
      data = create_host(data)
    else
      data.merge!("hostid" => hosts.first["hostid"])
      data.merge!("hostname" => hosts.first["host"])
    end
    data = create_item_or_web_scenario(data)
    create_trigger(data)
  end

  def create_item_or_web_scenario(data)
    #check what we will create
    case data["type"]
      when "web"
        create_httptest(data)
      when "ping", "tcp"
        create_item(data)
    end
  end

  def get_triggers_from_host
    host = connection.query(:method => "host.get",:params => {:output => ["host"],:selectInventory => ["alias"], :searchInventory => {:alias => "#{id}"}}).first
    connection.query(:method => "trigger.get", :params => { :output => "extend", :selectHosts => "extend", :selectItems => "extend", :hostids => host["hostid"] })
  end

  def connection
    return @connection unless @connection.nil?
    zcfg = ZabbixConfig::ZCFG[:location][region_id]
    @connection = ZabbixApi.connect(
    :url => zcfg[:url],
    :user => zcfg[:login],
    :password => zcfg[:password])
  end

  #Create trigger
  def create_trigger(data)
    case data["type"]
      when "ping", "tcp"
        #Create expression to check it
        delay_for_trigger  = create_delay_for_trigger(data["delay"],data["attempts"])
        data["expression"] = "{#{data["hostname"]}:#{data["key"]}.count(#{delay_for_trigger},0)}>=#{data["attempts"]}"
      when "web"
        data["expression"] = "{#{data["hostname"]}:web.test.fail[#{data["httptest"]}].count(#{data["delay"]},0)}<=#{data["attempts"]}"
        data["description"] = "#{data["url"]} #{data["code"]}"
    end
    connection.triggers.create(
      :description => data["description"],
      :comments => data["type"],
      :expression => data["expression"],
      :priority => data["priority"],
      :status     => 0,
      :hostid => data["hostid"],
      :url => data["attempts"],
      :type => 0 )
  end

  def create_host(data)
    data["hostname"] = generate_name
    host = connection.hosts.create({
      :host => data["hostname"],
      :interfaces => [
        {
          :type => "1",
          :main => "1",
          :useip => "1",
          :ip => "127.0.0.1",
          :port => "10050",
          :dns => "test"
        }
      ],
      :groups => [{:groupid => "2"}],
      :inventory_mode => "0",
      :inventory => {:alias => "#{id}", :name => evm_owner.email, :contact => evm_owner.name, :os => name}
     })
    data["hostid"] = host
    interface = connection.query(:method => "hostinterface.get",:params => {:output => ["interfaceid"], :hostids => data["hostid"]})
    data["interface_id"] = interface.first["interfaceid"]
    data
  end


  def create_httptest(data)
    name = generate_name
    connection.httptests.create(
      :name => name,
      :hostid => data["hostid"],
      :delay => data["delay"],
      :steps => [
        {
        :name => name,
        :url => data["url"],
        :status_codes => data["code"],
        :no => data["attempts"]
        }
       ],
      :agent => "Lynx/2.8.8rel.2 libwww-FM/2.14 SSL-MM/1.4.1"
     )
     data["httptest"] = name
     data
  end

  def remove_zabbix_host_by_owner(user)
    unless user.nil?
      host = connection.query(:method => "host.get",:params => {:output => ["host"],:selectInventory => ["alias"], :searchInventory => {:name => user.email}}).first
    end
    unless host.nil?
      connection.query(:method => "host.delete",:params => [host["hostid"]])
    end
  end

  def remove_zabbix_host_by_service
      host = connection.query(:method => "host.get",:params => {:output => ["host"],:selectInventory => ["alias"], :searchInventory => {:alias => "#{id}"}}).first
    unless host.nil?
      connection.query(:method => "host.delete",:params => [host["hostid"]])
    end
  end

  #Need to create interface for ping monitoring
  def create_interface(data)
    interface = connection.query(
      :method => "hostinterface.create",
      :params => {
        :hostid => data["hostid"],
        :dns => "test",
        :ip => data["ip"],
        :main => 0,
        :port => "10050",
        :type => "1",
      :useip => "1"
      })
    data["interface_id"] = interface["interfaceids"].first
    data
  end

  def create_item(data)
    name = generate_name
    case data["type"]
      when "tcp"
        data = get_interface(data)
        data["key"] = "net.tcp.service[\"tcp\",\"#{data["ip"]}\",\"#{data["port"]}\"]"
        data["description"] = "#{data["ip"]} #{data["port"]}"
      when "ping"
        data = create_interface(data)
        data["key"] = "icmpping[,,,]"
        data["description"] = "#{data["ip"]}"
    end
    connection.items.create(
      :name => name,
      :description => data["description"],
      :key_ => data["key"],
      :type => "3",
      :value_type => "3",
      :delay => data["delay"],
      :interfaceid => data["interface_id"],
      :history => "3600",
      :trends => "86400",
      :hostid => data["hostid"]
   )
    data
  end

  #Generate random names
  def generate_name
    value = ""
    8.times{value  << (65 + rand(25)).chr}
    value
  end

  def get_interface(data)
    interface = connection.query(:method => "hostinterface.get",:params => {:output => ["interfaceid"], :hostids => data["hostid"]})
    data["interface_id"] = interface.first["interfaceid"]
    data
  end

  def create_delay_for_trigger(delay, attempts)
    (delay[0].to_i * attempts.to_i).to_s + "m"
  end

  def create_frontend_data(data)
    new_data = []
    data.each do |data_item|
      time = parse_unix_time(data_item["items"].first["lastclock"])

      if time.nil?
        data_item["value"] = nil
      end

      description_item = parse_description(data_item)

      new_item = {
          status:           data_item["value"],
          monitoring_type:  data_item["comments"],
          time:             time,
          probes:           data_item["url"],
          url:              description_item["url"],
          ip:               description_item["ip"],
          code:             description_item["code"],
          port:             description_item["port"],
          delay:            data_item["items"].first["delay"],
          triggerid:        data_item["triggerid"],
          enabled:          data_item["status"]
      }
      new_data << new_item
    end

    new_data
  end

  def parse_description(data)
    description_hash = {}
    if data["comments"] == "web"
      data_description = data["description"].gsub(/\s+/m, ' ').strip.split(" ")
      description_hash = {"url" => data_description.first, "code" => data_description.second}
    elsif data["comments"] == "tcp"
      data_description = data["description"].gsub(/\s+/m, ' ').strip.split(" ")
      description_hash = {"ip" => data_description.first, "port" => data_description.second}
    else
      data_description = data["description"].gsub(/\s+/m, ' ').strip.split(" ")
      description_hash = {"ip" => data_description.first}
    end
  end

   def parse_unix_time(data)
     time = DateTime.strptime(data.to_s,'%s')
     if time == DateTime.strptime(0.to_s,'%s')
       time = nil
     end
     time
   end

end
