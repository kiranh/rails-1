require 'action_service/support/class_inheritable_options'
require 'action_service/support/signature'

module ActionService # :nodoc:
  class ActionServiceError < StandardError # :nodoc:
  end

  # An Action Service object implements a specified API.
  #
  # Used by controllers operating in _Delegated_ dispatching mode.
  #
  # ==== Example
  # 
  #   class PersonService < ActionService::Base
  #     web_service_api PersonAPI
  #
  #     def find_person(criteria)
  #       Person.find_all [...]
  #     end
  #
  #     def delete_person(id)
  #       Person.find_by_id(id).destroy
  #     end
  #   end
  #
  #   class PersonAPI < ActionService::API::Base
  #     api_method :find_person,   :expects => [SearchCriteria], :returns => [[Person]]
  #     api_method :delete_person, :expects => [:int]
  #   end
  #
  #   class SearchCriteria < ActionStruct::Base
  #     member :firstname, :string
  #     member :lastname,  :string
  #     member :email,     :string
  #   end
  class Base
    # Whether to report exceptions back to the caller in the protocol's exception
    # format
    class_inheritable_option :web_service_exception_reporting, true
  end
end
