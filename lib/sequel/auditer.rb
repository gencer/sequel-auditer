require 'sequel/auditer/railtie'
require 'sequel/auditer/version'

module Sequel
  module Auditer
    CREATE  = 'create'.freeze
    UPDATE  = 'update'.freeze
    DESTROY = 'destroy'.freeze

    # set the name of the global method that provides the current user. Default: :current_user
    @auditer_current_user_method      = :current_user
    # set any additional info such as :ip, :user_agent, ...
    @auditer_additional_info_method   = :additional_info
    @auditer_resource_owner_method    = :owner_method
    # enable swapping of the Audit model
    @auditer_model_name               = :AuditLog
    # toggle for enabling / disabling auditing
    @auditer_enabled                  = true

    # by default ignore these columns
    @auditer_default_ignored_columns  = [
      :id, :ref, :password, :password_hash,
      :lock_version,
      :created_at, :updated_at, :created_on, :updated_on
    ]

    class << self
      attr_accessor :auditer_current_user_method,
                    :auditer_additional_info_method,
                    :auditer_model_name,
                    :auditer_enabled,
                    :auditer_default_ignored_columns,
                    :auditer_resource_owner_field
    end
  end
end
