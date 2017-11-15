module QuotaMixin
  extend ActiveSupport::Concern

  QUOTA_BASE = {
      :storage_allocated   => {
          :unit          => :bytes,
          :format        => :gigabytes_human,
          :text_modifier => "GB".freeze
      },
      :svm_allocated => {
          :unit          => :fixnum,
          :format        => :general_number_precision_0,
          :text_modifier => "Count".freeze
      },
      :hours_allocated => {
          :unit          => :fixnum,
          :format        => :general_number_precision_0,
          :text_modifier => "Count".freeze
      },
  }

  DEFAULT_TEXT_FOR_ZERO_VALUES = {
      :total     => "Not defined".freeze,
      :available => "Not applicable".freeze
  }

  NAMES = QUOTA_BASE.keys.map(&:to_s)

  included do
    validates :unit, :value, :presence => true
    validates :value, :numericality => {:greater_than => 0}
    validates :warn_value, :numericality => {:greater_than => 0}, :if => "warn_value.present?"

    scope :storage_allocated,   -> { where(:name => :storage_allocated) }
    scope :svm_allocated,       -> { where(:name => :svm_allocated) }
    scope :hours_allocated,     -> { where(:name => :hours_allocated) }

    virtual_column :name, :type => :string
    virtual_column :total, :type => :integer
    virtual_column :used, :type => :float
    virtual_column :allocated, :type => :float
    virtual_column :available, :type => :float

    alias_attribute :total, :value

    before_validation(:on => :create) do
      self.unit = default_unit unless unit.present?
    end

  end


  def quota_hash
    self.class.quota_definitions[name.to_sym].merge(:unit => unit, :value => value, :warn_value => warn_value, :format => format) # attributes
  end

  def format
    self.class.quota_definitions.fetch_path(name.to_sym, :format).to_s
  end

  def default_unit
    self.class.quota_definitions.fetch_path(name.to_sym, :unit).to_s
  end

  def quotable_resource_quota(quotable_resource)
    quotable_resource.quotas.send(name).take
  end

  def quota_additionally_requested
    oval, nval = changes["value"]
    (nval || 0) - (oval || 0)
  end

  def required_larger_then_consumed_errors
    oval, nval = changes["value"]
    if nval < allocated
      errors.add(:base, "Specified [#{name}] quota can't be less than quota already allocated. Requested:
                        #{self.class.format_value(nval, name)}, allocated: #{self.class.format_value(allocated, name)}")
    elsif nval < used
      errors.add(:base, "Specified [#{name}] quota can't be less than quota already used. Requested:
                        #{self.class.format_value(nval, name)}, used: #{self.class.format_value(used, name)}")
    end
  end

  def parent_quota_lack_errors(parent, requested)
    # Check if the parent has enough quota available to give to the child
    parent_quota = quotable_resource_quota(parent)
    if parent_quota.nil?
      errors.add(:base, "Quota [#{name}] of parent #{parent.resource_type} [#{parent.name}] isn't set. It should present to allow editing this quota [#{name}]")
    elsif parent_quota.available < requested
      errors.add(:base, "Quota [#{name}] of parent #{parent.resource_type} [#{parent.name}] is over allocated. Requested:
                        #{self.class.format_value(requested, name)}, available: #{self.class.format_value(parent_quota.available, parent_quota.name)}")
    end
  end

  def validate_quota_base(parent)
    return if parent.nil?
    return unless value_changed?
    requested = quota_additionally_requested
    parent_quota_lack_errors(parent, requested)
    required_larger_then_consumed_errors
    return errors
  end

  module ClassMethods

    def format_value(value, name)
      units = QUOTA_BASE[name.to_sym][:text_modifier]
      if name == "storage_allocated"
        "#{(value/1.gigabyte).round(1)} #{units}"
      else
        "#{value.round(1)} #{units}"
      end
    end

    def can_format_field?(field, quota_name)
      table_field, = field.split(".")
      to_s.tableize == table_field ? NAMES.include?(quota_name) : false
    end

    def default_text_for(metric)
      DEFAULT_TEXT_FOR_ZERO_VALUES[metric]
    end

    # remove all quotas that are not listed in the keys to keep
    # e.g.: tenant.tenant_quotas.destroy_missing_quotas(include_keys)
    # NOTE: these are already local, no need to hit db to find them
    def destroy_missing(keep)
      keep = keep.map(&:to_s)
      deletes = all.select { |tq| !keep.include?(tq.name) }
      delete(deletes)
    end

    def quota_description(name)
      case name
        when :cpu_allocated
          _("Allocated Virtual CPUs")
        when :mem_allocated
          _("Allocated Memory in GB")
        when :storage_allocated
          _("Allocated Storage in GB")
        when :vms_allocated
          _("Allocated Number of Virtual Machines")
        when :templates_allocated
          _("Allocated Number of Templates")
        when :svm_allocated
          _("Allocated Number of SVM")
        when :hours_allocated
          _("Allocated Number of SVM Hours")
      end
    end
    
    alias tenant_quota_description quota_description

    def quota_definitions
      @quota_definitions ||= QUOTA_BASE.each_with_object({}) do |(name, value), h|
        h[name] = value.merge(:description => quota_description(name), :value => nil, :warn_value => nil)
      end
    end

    def service_template
      ServiceTemplate.find_by_generic_subtype("quota")
    end
  end
end
