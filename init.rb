# Include hook code here
ActionController::Base.class_eval do
  include LastFm
end