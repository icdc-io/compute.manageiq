module TenantTagsMixin
  extend ActiveSupport::Concern

  included do
  end

  def managers_tags
    tags.select { |tag| tag.name =~ /\/managed\/manager\// }
  end

  def managers
    manager_tags = tags.select{ |tag| /\/managed\/manager\// =~ tag.name }
    
    manager_tags.map do |manager_tag| 
      User.in_region(self.my_region_number).find_by(userid: self.class.email_from_tag(manager_tag))
    end
  end

  def account?
    tags.collect{ |tag| tag.name }.include?("/managed/account/true")
  end

  def destroy_tags(options = {})
    ns = Tag.get_namespace(options)
    
    tag = Tag.arel_table
    tagging = Tagging.arel_table
    Tagging.joins(:tag)
        .where(:taggable_id    => id)
        .where(:taggable_type  => self.class.base_class.name)
        .where(tagging[:tag_id].eq(tag[:id]))
        .where(tag[:name].matches "#{ns}/%")
        .destroy_all
  end

  module ClassMethods
    def email_from_tag(manager_tag)
      User.tags2emails[manager_tag.name.split('/')[3]]
    end
  end

end

