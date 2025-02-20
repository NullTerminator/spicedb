# frozen_string_literal: true

module Spicedb
  module Management
    def self.create_role(organization_id, role_id)
      Spicedb.add_relationship('role', role_id, 'organization', 'organization', organization_id)
    end

    def self.create_group(organization_id, group_id)
      Spicedb.add_relationship('group', group_id, 'organization', 'organization', organization_id)
    end

    def self.add_permission_to_role(organization_id, product, action, role_id)
      unless Spicedb.permission_map&.dig(product.to_sym)&.include?(action.to_sym)
        puts 'INVALID PERMISSION'
        return
      end

      Spicedb.add_relationship('organization', organization_id, product_permission(product, action), 'role', role_id, 'member')
    end

    def self.add_role_to_user(role_id, user_id)
      Spicedb.add_relationship('role', role_id, 'member', 'user', user_id)
    end

    def self.add_user_to_group(user_id, group_id)
      Spicedb.add_relationship('group', group_id, 'member', 'user', user_id)
    end

    def self.write_schema
      Spicedb.client.schema_service.write_schema(
        Authzed::Api::V1::WriteSchemaRequest.new(schema: build_schema)
      )
    end

    def self.read_schema
      Spicedb.client.schema_service.read_schema(Authzed::Api::V1::ReadSchemaRequest.new)
    end

    private

    def self.product_permission(product, action)
      "#{product}_#{action}"
    end

    def self.build_schema
      <<~SCHEMA
definition user {}

definition organization {
#{
  Spicedb.permission_map.flat_map do |product, actions|
    actions.map do |action|
      "relation #{product_permission(product, action)}: role#member\n" \
      "permission #{action}_#{product} = #{product_permission(product, action)}"
    end
  end.join("\n")
}
}

definition role {
  relation member: user
  relation organization: organization
}


definition group {
	relation member: user
	relation organization: organization
}

#{
  Spicedb.permission_map.flat_map do |product, actions|
    prod = "definition #{product} {\n" \
           "  relation organization: organization\n" \
           "  relation accessors: user | group#member\n"

    perms = actions.map do |action|
      perm = "permission #{action} = organization->#{action}_#{product}"
      perm += "& accessors" if action != 'create'
      perm
    end.join("\n")

    "#{prod}#{perms}\n}"
  end.join("\n")
}
      SCHEMA
    end
  end
end
