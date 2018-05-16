module TagsEmailsMixin
  extend ActiveSupport::Concern

  included do
  end

  
  module ClassMethods

    def tags2emails(update = false)
      
      if update == true || (defined?(@@tags2emails)).nil? 
        @@tags2emails = User.in_my_region.all.each_with_object({}) do |user, h| 
          h[User.email2tag(user.email)] = user.email unless user.email.nil? 
        end
      end

      @@tags2emails
    end

  end

end

