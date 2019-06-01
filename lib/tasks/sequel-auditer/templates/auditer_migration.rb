Sequel.migration do
  # created by sequel-auditer gem

  change do
    create_table(:audit_logs) do
      primary_key :id
      String      :associated_type
      Integer     :associated_id
      String      :event
      String      :changed, text: true
      Integer     :version
      Integer     :modifier_id
      Integer     :resource_owner_id
      String      :modifier_type
      String      :resource_owner_type
      String      :additional_info, text: true
      DateTime    :created_at

      index %i[associated_type associated_id]
      index %i[modifier_type modifier_id]
    end
  end
end
