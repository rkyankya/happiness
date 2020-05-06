class SortCurriculumResourcesMutator < ApplicationQuery
  property :resource_ids, validates: { presence: true }
  property :resource_type, validates: { inclusion: { in: [TargetGroup.name, Target.name] } }

  validate :must_belong_to_same_parent

  def sort
    resource_class.transaction do
      resources.each do |resource|
        resource.update!(sort_index: resource_ids.index(resource.id.to_s))
      end
    end
  end

  def must_belong_to_same_parent
    return unless resource_type.in?([TargetGroup.name, Target.name])

    return if resources.distinct.pluck(parent_resource_identifier).one?

    errors[:base] << "#{resource_type} must belong to the same parent resource"
  end

  private

  def parent_resource_identifier
    if resource_type == TargetGroup.name
      :level_id
    else
      :target_group_id
    end
  end

  def resource_class
    if resource_type == TargetGroup.name
      TargetGroup
    else
      Target
    end
  end

  def resources
    @resources ||= begin
      if resource_type == TargetGroup.name
        current_school.target_groups.where(id: resource_ids)
      else
        current_school.targets.where(id: resource_ids)
      end
    end
  end

  def course
    resources.first.level.course
  end

  def authorized?
    current_school_admin.present? || current_user.course_authors.where(course: course).exists?
  end
end
