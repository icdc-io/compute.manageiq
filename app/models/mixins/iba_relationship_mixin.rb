require 'memoist'

module IbaRelationshipMixin
  extend ActiveSupport::Concern

  def iba_ancestor_ids(*args)
    master_ids = ancestor_ids(*args)
    ids = []
    m_id = self.id % 100000
    ids = ids + Tenant.where("id % 100000 = ?", m_id) 
    for master_id in master_ids
      m_id = master_id % 100000 
      t_ids = Tenant.where("id % 100000 = ?", m_id)
      ids = ids + t_ids
    end
    ids
  end

  def iba_descendant_ids(*args)
    master_ids = descendant_ids(*args)
    ids = []
    m_id = self.id % 100000
    ids = ids + Tenant.where("id % 100000 = ?", m_id)
    for master_id in master_ids
      m_id = master_id % 100000
      t_ids = Tenant.where("id % 100000 = ?", m_id)
      ids = ids + t_ids
    end
    ids
  end
end
