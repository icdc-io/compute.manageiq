module QuotableMixin
  extend ActiveSupport::Concern

  included do
  end

  def get_quotas_base(quotas)
    quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash
    end.reverse_merge(Quota.quota_definitions)
  end

  def set_quotas_base(assoc_quotas, quota)
    updated_keys = []
    self.class.transaction do
      quota.each do |name, values|
        next if values[:value].nil?
        name = name.to_s
        q = assoc_quotas.detect { |tq| tq.name == name } || assoc_quotas.build(:name => name)
        q.update_attributes!(values)
        updated_keys << name
      end
      assoc_quotas.destroy_missing(updated_keys)
      clear_association_cache
    end
    get_quotas_base(assoc_quotas)
  end

  def quota_consumption(quotas, qtype)
    quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash.merge(:value => q.send(qtype))
    end.reverse_merge(Quota.quota_definitions)
  end

  def used_quotas_base(quotas)
    quota_consumption(quotas, :used)
  end

  def allocated_quotas_base(quotas)
    quota_consumption(quotas, :allocated)
  end

  def available_quotas_base(quotas)
    quota_consumption(quotas, :available)
  end

  def combined_quotas_base(quotas)
    quotas.each_with_object({}) do |q, h|
      h[q.name.to_sym] = q.quota_hash
      h[q.name.to_sym][:allocated]   = q.allocated
      h[q.name.to_sym][:available]   = q.available
      h[q.name.to_sym][:used]        = q.used
    end.reverse_merge(Quota.quota_definitions)
  end

  def combine_quotas(quota1, quota2)
    quota_names = [:storage_allocated, :svm_allocated, :hours_allocated]
    quota_fields = [:value, :allocated, :available, :used]
    if quota1["quota"]
      quota_names.each do |quota_name|
        if quota1["quota"][quota_name][:value] && quota2["quota"][quota_name][:value]
          quota_fields.each do |field|
            quota1["quota"][quota_name][field] += quota2["quota"][quota_name][field]
          end
        elsif quota2["quota"][quota_name][:value]
          quota1["quota"][quota_name] = quota2["quota"][quota_name]
        end
      end
    else
      quota1["quota"] = Marshal.load(Marshal.dump(quota2["quota"]))
    end
  end

  def manage_locations(node, id=nil)
    if id.nil?
      _, id = self.class.split_id(self.id)
    end

    for slave_region in MiqRegion.all
      next if slave_region.default?
      node_in_region = self.class.find_by_id(self.class.id_in_region(id, slave_region.region))
      next unless node_in_region
      location_resources = {
          "id" => node_in_region.id,
          "name" => slave_region.description,
          "full_name" => slave_region.full_name,
          "chargeback" => [],
          "quota" => node_in_region.combined_quotas
      }
      node["locations"].push(location_resources)
    end
    sum_node_resources_by_locations(node)
  end

  def sum_node_resources_by_locations(parent_node)
    return if parent_node["locations"].empty?

    locs_hash = parent_node["children"].flat_map { |node| node["locations"] }
    grouped_locs = locs_hash.group_by { |location| location["name"] }
    grouped_locs.each do |loc_name, loc_resources|
      location = parent_node["locations"].find { |loc| loc["name"] == loc_name }
      loc_resources.each do |loc_res|
        location["chargeback"] = combine_chargebacks(location["chargeback"], loc_res["chargeback"])
      end
    end
  end

  def set_edit_action_to_children node
    for child in node["children"]
      child["edit_action"] = "edit" unless child.nil?
    end
  end

  def resource_type
    self.class.name.underscore
  end

  def quotas
    self.send("#{self.resource_type}_quotas")
  end

  def quota_by_name(name)
    self.quotas.find { |quota| quota[:name] == name }
  end

  def validate_test_quotas(quotas_hash)
    quotas_hash.each do |quota_name, test_value|
      quota = self.quota_by_name(quota_name)
      unless quota.nil?
        quota.value = test_value
        quota.validate_quota
      end
    end
  end

  module ClassMethods
   def search_attribute
      if self.column_names.include? 'name'
        :name
      elsif self.column_names.include? 'description'
        :description
      end
    end
  end
end
