class CreateCommunityMutator < ApplicationQuery
  include AuthorizeSchoolAdmin

  property :name, validates: { length: { minimum: 1, maximum: 50, message: 'InvalidLengthName' } }
  property :target_linkable
  property :course_ids

  validate :course_must_exist_in_current_school

  def course_must_exist_in_current_school
    return if courses.count == course_ids.count

    errors[:base] << 'IncorrectCourseIds'
  end

  def create_community
    Community.create!(
      name: name,
      target_linkable: target_linkable,
      school: current_school,
      courses: courses
    ).id
  end

  private

  def courses
    @courses ||= current_school.courses.where(id: course_ids)
  end
end
