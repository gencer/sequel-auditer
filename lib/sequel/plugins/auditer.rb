require_relative '../auditer'

class AuditLog < Sequel::Model
  # handle versioning of audited records
  plugin :list, field: :version, scope: [:associated_type, :associated_id]
  plugin :timestamps
  plugin :polymorphic

  # TODO: see if we should add these
  many_to_one :associated, polymorphic: true
  many_to_one :modifier,   polymorphic: true

  def before_validation
    # grab the current user
    if u = audit_user
      self.modifier = u
    end
	
	# grab any additional info if any
	if i = audit_additional_info
      self.additional_info = i
    end
	
    super
  end

  # private

  # Obtains the `current_user` based upon the `:auditer_current_user_method' value set in the
  # audited model, either via defaults or via :user_method config options
  #
  # # NOTE! this allows overriding the default value on a per audited model
  def audit_user
    m = Kernel.const_get(associated_type)
    m.send(m.auditer_current_user_method) || send(m.auditer_current_user_method)
  end
  
  def audit_additional_info
    m = Kernel.const_get(associated_type)
    m.send(m.auditer_additional_info_method) || send(m.auditer_additional_info_method)
  end

end

module Sequel
  module Plugins

    # Given a Post model with these fields:
    #   [:id, :category_id, :title, :body, :author_id, :created_at, :updated_at]
    #
    #
    # All fields
    #   plugin :auditer
    #     #=> [:category_id, :title, :body, :author_id]  # NB! excluding @default_ignore_attrs
    #     #=> [:id, :created_at, :updated_at]
    #
    # Single field
    #   plugin :auditer, only: :title
    #   plugin :auditer, only: [:title]
    #     #=> [:title]
    #     #+> [:id, :category_id, :body, :author_id, :created_at, :updated_at] # ignored fields
    #
    # Multiple fields
    #   plugin :auditer, only: [:title, :body]
    #     #=> [:title, :body] # tracked fields
    #     #=> [:id, :category_id, :author_id, :created_at, :updated_at] # ignored fields
    #
    #
    # All fields except certain fields
    #   plugin :auditer, except: :title
    #   plugin :auditer, except: [:title]
    #     #=> [:id, :category_id, :author_id, :created_at, :updated_at] # tracked fields
    #     #=> [:title] # ignored fields
    #
    #
    #
    module Auditer

      # called when
      def self.configure(model, opts = {})
        model.instance_eval do
          # add support for :dirty attributes tracking & JSON serializing of data
          plugin(:dirty)
          plugin(:json_serializer)
          plugin(:polymorphic)

          # set the default ignored columns or revert to defaults
          set_default_ignored_columns(opts)
          # sets the name of the current User method or revert to default: :current_user
          # specifically for the audited model on a per model basis
          set_user_method(opts)
          set_additional_info_method(opts)

          set_reference_method(opts)

          only    = opts.fetch(:only, [])
          except  = opts.fetch(:except, [])

          unless only.empty?
            # we should only track the provided column
            included_columns = [only].flatten
            # subtract the 'only' columns from all columns to get excluded_columns
            excluded_columns = columns - included_columns
          else # except:
            # all columns minus any excepted columns and default ignored columns
            included_columns = [
              [columns - [except].flatten].flatten - @auditer_default_ignored_columns
            ].flatten.uniq

            # except_columns = except.empty? ? [] : [except].flatten
            excluded_columns = [columns - included_columns].flatten.uniq
            # excluded_columns = [columns - [except_columns, included_columns].flatten].flatten.uniq
          end

          @auditer_included_columns = included_columns
          @auditer_ignored_columns  = excluded_columns

          # each included model will have an associated versions
          one_to_many(
            :versions,
            class: audit_model_name,
            as: 'associated'
          )

        end


      end

      #
      module ClassMethods

        attr_accessor :auditer_default_ignored_columns, :auditer_current_user_method, :auditer_additional_info_method
        # The holder of ignored columns
        attr_reader :auditer_ignored_columns
        # The holder of columns that should be audited
        attr_reader :auditer_included_columns

        attr_accessor :auditer_reference_method


        Plugins.inherited_instance_variables(self,
                                             :@auditer_default_ignored_columns => nil,
                                             :@auditer_current_user_method     => nil,
                                             :@auditer_additional_info_method  => nil,
                                             :@auditer_included_columns        => nil,
                                             :@auditer_ignored_columns         => nil,
                                             :@auditer_reference_method        => nil
                                            )

        def non_audited_columns
          columns - auditer_columns
        end

        def auditer_columns
          @auditer_columns ||= columns - @auditer_ignored_columns
        end

        # def default_ignored_attrs
        #   # TODO: how to reference the models primary_key value??
        #   arr = [pk.to_s]
        #   # handle STI (Class Table Inheritance) models with `plugin :single_table_inheritance`
        #   arr << 'sti_key' if self.respond_to?(:sti_key)
        #   arr
        # end

        #
        # returns true / false if any audits have been made
        #
        #   Post.auditer_versions?   #=> true / false
        #
        def auditer_versions?
          audit_model.where(associated_type: name.to_s).count >= 1
        end

        # grab all audits for a particular model based upon filters
        #
        #   Posts.auditer_versions(:model_pk => 123)
        #     #=> filtered by primary_key value
        #
        #   Posts.auditer_versions(:user_id => 88)
        #     #=> filtered by user name
        #
        #   Posts.auditer_versions(:created_at < Date.today - 2)
        #     #=> filtered to last two (2) days only
        #
        #   Posts.auditer_versions(:created_at > Date.today - 7)
        #     #=> filtered to older than last seven (7) days
        #
        def auditer_versions(opts = {})
          audit_model.where(opts.merge(associated_type: name.to_s)).order(:version).all
        end


        private


        def audit_model
          const_get(audit_model_name)
        end

        def audit_model_name
          ::Sequel::Auditer.auditer_model_name
        end

        def set_default_ignored_columns(opts)
          if opts[:default_ignored_columns]
            @auditer_default_ignored_columns = opts[:default_ignored_columns]
          else
            @auditer_default_ignored_columns = ::Sequel::Auditer.auditer_default_ignored_columns
          end
        end

        def set_user_method(opts)
          if opts[:user_method]
            @auditer_current_user_method = opts[:user_method]
          else
            @auditer_current_user_method = ::Sequel::Auditer.auditer_current_user_method
          end
        end

        def set_additional_info_method(opts)
          if opts[:additional_info]
            @auditer_additional_info_method = opts[:additional_info]
          else
            @auditer_additional_info_method = ::Sequel::Auditer.auditer_additional_info_method
          end
        end

        def set_reference_method(opts)
          if opts[:reference_method]
            @auditer_reference_method = opts[:reference_method]
          end
        end

      end


      #
      module InstanceMethods

        # Returns who put the post into its current state.
        #
        #   post.blame  # => 'joeblogs'
        #
        #   post.last_audited_by  # => 'joeblogs'
        #
        # Note! returns 'not audited' if there's no audited version (new unsaved record)
        #
        def blame
          v = versions.last unless versions.empty?
          v ? v.modifier : 'not audited'
        end
        alias_method :last_audited_by, :blame

        # Returns who put the post into its current state.
        #
        #   post.last_audited_at  # => '2015-12-19 @ 08:24:45'
        #
        #   post.last_audited_on  # => 'joeblogs'
        #
        # Note! returns 'not audited' if there's no audited version (new unsaved record)
        #
        def last_audited_at
          v = versions.last unless versions.empty?
          v ? v.created_at : 'not audited'
        end
        alias_method :last_audited_on, :last_audited_at

        private

        # extract audited values only
        def auditer_values(event)
          vals = case event
          when Sequel::Auditer::CREATE
            self.values
          when Sequel::Auditer::UPDATE
            (column_changes.empty? ? previous_changes : column_changes)
          when Sequel::Auditer::DESTROY
            self.values
          end
          vals.except(*model.auditer_default_ignored_columns)
        end

        def add_audited(event)
          changed = audited_values(event)
          unless changed.blank?
            add_version(
              event:      event,
              changed:    changed
            )
          end
        end

        ### CALLBACKS ###

        def after_create
          super
          add_audited(Sequel::Auditer::CREATE)
        end

        def after_update
          super
          add_audited(Sequel::Auditer::UPDATE)
        end

        def after_destroy
          super
          add_audited(Sequel::Auditer::DESTROY)
        end
      end
    end
  end
end
