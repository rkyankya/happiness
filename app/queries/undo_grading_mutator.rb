class UndoGradingMutator < ApplicationQuery
  include AuthorizeCoach

  property :submission_id, validates: { presence: true }

  validate :must_be_graded

  def undo_grading
    TimelineEvent.transaction do
      # Clear existing grades
      TimelineEventGrade.where(timeline_event: submission).destroy_all
      # Clear evaluation info
      submission.update!(passed_at: nil, evaluator_id: nil, evaluated_at: nil, checklist: checklist)
    end
  end

  private

  def must_be_graded
    return if submission&.evaluator_id?

    errors[:base] << 'Could not find a graded submission with the given ID'
  end

  def checklist
    submission.checklist.map do |c|
      c['status'] = TimelineEvent::CHECKLIST_STATUS_NO_ANSWER
      c
    end
  end

  def submission
    @submission = current_school.timeline_events.where(id: submission_id).first
  end

  def course
    @course ||= submission&.target&.course
  end
end
