require 'memoist'

module IbaRelationshipMixin
  extend ActiveSupport::Concern


  def tenants_in_regions_by_ids(ids)
    tenants = []
    ids.each do |id|
      tenants.push( *Tenant.where(name: Tenant.find(id).name) )
    end

    tenants
  end

  def iba_ancestor_ids(*args)
    master_ids = ancestor_ids(*args)
    tenants_in_regions_by_ids(master_ids.push(self.id))
  end

  def iba_descendant_ids(*args)
    master_ids = descendant_ids(*args)
    tenants_in_regions_by_ids(master_ids.push(self.id))
  end

  def iba_managed_descendant_ids(*args)
    master_ids = descendant_ids(*args)
    for tenant in User.current_user.managed_tenant
      master_ids.push(tenant.id)
      master_ids += tenant.descendant_ids
    end
    tenants_in_regions_by_ids(master_ids.push(self.id))
  end

  def iba_managed_descendants(*args)
    ids = iba_managed_descendant_ids(*args)
    Tenant.where(id: ids)
  end

  def iba_sibling_ids(*args)
    master_ids = sibling_ids(*args)
    tenants_in_regions_by_ids(master_ids.push(self.id))
  end

  def iba_siblings(*args)
    ids = iba_sibling_ids(*args)
    Tenant.where(id: ids)
  end

  def icdc_sibling_ids(*args)
    master_ids = []
    case (User.current_user.current_group.miq_user_role.name)
    when "ICDC-member"
       master_ids.push(User.current_user.current_group.tenant.id)
       tenants_in_regions_by_ids(master_ids.push(self.id))
    when "ICDC-admin"
      master_ids = iba_descendant_ids(*args)
      tenants_in_regions_by_ids(master_ids.push(self.id))
    when "ICDC-billing"
      master_ids = iba_descendant_ids(*args)
      tenants_in_regions_by_ids(master_ids.push(self.id))
    when "ICDC-project-admin"
      master_ids.push(User.current_user.current_group.tenant.id)
      tenants_in_regions_by_ids(master_ids.push(self.id))
    else
      master_ids.push(User.current_user.current_group.tenant.id)
      tenants_in_regions_by_ids(master_ids.push(self.id))
    end
  end

  def icdc_siblings(*args)
    ids = icdc_sibling_ids(*args)
    Tenant.where(id: ids)
  end

end
