# ahrechushkin: OpenStruct override method :try
#               https://github.com/ruby/ostruct/issues/42
OpenStruct.class_eval do
  alias_method :try, :public_send
  remove_method :try! if method_defined?(:try!)
end
