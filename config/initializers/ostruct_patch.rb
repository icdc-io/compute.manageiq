# ahrechushkin: OpenStruct override method :try
#               https://github.com/ruby/ostruct/issues/42
OpenStruct.class_eval do
  alias_method :try, :public_send
end
