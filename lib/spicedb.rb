# frozen_string_literal: true

require_relative "spicedb/configuration"
require_relative "spicedb/version"

require 'authzed'

module Spicedb
  class Error < StandardError; end

  def self.add_record(organization_id, record)
    add_relationship(underscore(record.class.name), record.id, 'organization', 'organization', organization_id)
  end

  def self.add_access_to_record(record, user_id: nil, group_id: nil)
    if user_id
      add_relationship(underscore(record.class.name), record.id, 'accessors', 'user', user_id)
    elsif group_id
      add_relationship(underscore(record.class.name), record.id, 'accessors', 'group', group_id, 'member')
    else
      raise ArgumentError, 'Must provide user_id or group_id'
    end
  end

  def self.has_permission?(record, permission, user_id)
    check_permission(underscore(record.class.name), record.id, permission, 'user', user_id)
  end

  def self.can?(action, product, user_id, organization_id)
    check_permission('organization', organization_id, "#{product}_#{action}", 'user', user_id)
  end

  def self.get_all_users_with_access_to(record)
    client.permissions_service.lookup_subjects(Authzed::Api::V1::LookupSubjectsRequest.new(
      consistency: Authzed::Api::V1::Consistency.new(fully_consistent: true),
      resource: Authzed::Api::V1::ObjectReference.new(object_type: underscore(record.class.name), object_id: record.id),
      permission: 'accessors',
      subject_object_type: 'user'
    )).map(&:subject_object_id)
  end

  def self.get_all_accessors_to(record)
    client.permissions_service.read_relationships(Authzed::Api::V1::ReadRelationshipsRequest.new(
      consistency: Authzed::Api::V1::Consistency.new(fully_consistent: true),
      relationship_filter: Authzed::Api::V1::RelationshipFilter.new(
        resource_type: underscore(record.class.name),
        optional_resource_id: record.id,
        optional_relation: "accessors"
      )
    )).map { |r| r.relationship.subject.object }.map { |o| "#{o.object_type}:#{o.object_id}" }
  end

  private

  def self.client
    @client ||= Authzed::Api::V1::Client.new(
      **{
        target: url,
        credentials: tls ? nil : :this_channel_is_insecure,
        interceptors: [Authzed::GrpcUtil::BearerToken.new(token: token)]
      }.compact
    )
  end

  def self.underscore(camel_cased_word)
    camel_cased_word.to_s.gsub(/::/, '/')
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end

  def self.add_relationship(resource_type, resource_id, relation, subject_type, subject_id, subject_relation = nil)
    resource = Authzed::Api::V1::ObjectReference.new(object_type: resource_type, object_id: resource_id)
    subject = Authzed::Api::V1::SubjectReference.new(
      **{
        object: Authzed::Api::V1::ObjectReference.new(object_type: subject_type, object_id: subject_id),
        optional_relation: subject_relation
      }.compact
    )

    client.permissions_service.write_relationships(
      Authzed::Api::V1::WriteRelationshipsRequest.new(
        updates: [
          Authzed::Api::V1::RelationshipUpdate.new(
            operation: Authzed::Api::V1::RelationshipUpdate::Operation::OPERATION_CREATE,
            relationship: Authzed::Api::V1::Relationship.new(
              resource: resource,
              relation: relation,
              subject: subject
            )
          )
        ]
      )
    )
  end

  def self.check_permission(resource_type, resource_id, permission, subject_type, subject_id)
    resp = client.permissions_service.check_permission(Authzed::Api::V1::CheckPermissionRequest.new(
      consistency: Authzed::Api::V1::Consistency.new(fully_consistent: true),
      resource: Authzed::Api::V1::ObjectReference.new(object_type: resource_type, object_id: resource_id),
      permission: permission,
      subject: Authzed::Api::V1::SubjectReference.new(
        object: Authzed::Api::V1::ObjectReference.new(object_type: subject_type, object_id: subject_id),
      )
    ))

    result = Authzed::Api::V1::CheckPermissionResponse::Permissionship.resolve(resp.permissionship)
    result == Authzed::Api::V1::CheckPermissionResponse::Permissionship::PERMISSIONSHIP_HAS_PERMISSION
  end
end
