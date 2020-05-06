require 'rails_helper'

feature 'Submissions show' do
  include UserSpecHelper
  include MarkdownEditorHelper
  include NotificationHelper
  include SubmissionsHelper

  let(:school) { create :school, :current }
  let(:course) { create :course, school: school }
  let(:level) { create :level, :one, course: course }
  let(:target_group) { create :target_group, level: level }
  let(:target) { create :target, :for_founders, target_group: target_group }
  let(:target_2) { create :target, :for_founders, target_group: target_group }
  let(:auto_verify_target) { create :target, :for_founders, target_group: target_group }
  let(:grade_labels_for_1) { [{ 'grade' => 1, 'label' => 'Bad' }, { 'grade' => 2, 'label' => 'Good' }, { 'grade' => 3, 'label' => 'Great' }, { 'grade' => 4, 'label' => 'Wow' }] }
  let(:evaluation_criterion_1) { create :evaluation_criterion, course: course, max_grade: 4, pass_grade: 2, grade_labels: grade_labels_for_1 }
  let(:evaluation_criterion_2) { create :evaluation_criterion, course: course }

  let(:team) { create :startup, level: level }
  let(:coach) { create :faculty, school: school }
  let(:team_coach_user) { create :user, name: 'John Doe' }
  let(:team_coach) { create :faculty, school: school, user: team_coach_user }
  let(:school_admin) { create :school_admin }

  before do
    create :faculty_course_enrollment, faculty: coach, course: course
    create :faculty_course_enrollment, faculty: team_coach, course: course
    create :faculty_startup_enrollment, :with_course_enrollment, faculty: team_coach, startup: team

    # Set evaluation criteria on the target so that its submissions can be reviewed.
    target.evaluation_criteria << [evaluation_criterion_1, evaluation_criterion_2]
    target_2.evaluation_criteria << [evaluation_criterion_1, evaluation_criterion_2]
  end

  context 'with a pending submission' do
    let(:submission_pending) { create(:timeline_event, latest: true, target: target) }
    let(:submission_pending_2) { create(:timeline_event, latest: true, target: target_2) }
    let(:student) { team.founders.first }

    before do
      submission_pending.founders << student
      submission_pending_2.founders << student
    end

    scenario 'coach visits submission show', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_pending)

      within("div[aria-label='submissions-overlay-header']") do
        expect(page).to have_content('Level 1')
        expect(page).to have_content("Submitted by #{student.name}")
        expect(page).to have_link(student.name, href: "/students/#{student.id}/report")
        expect(page).to have_link(target.title, href: "/targets/#{target.id}")
        expect(page).to have_content(target.title)
        expect(page).to have_text 'Assigned Coaches'

        # Hovering over the avatar should reveal the name of the assigned coach.
        page.find('svg', text: 'JD').hover
        expect(page).to have_text('John Doe')
      end

      expect(page).to have_content('Add Your Feedback')
      expect(page).to have_content('Grade Card')
      expect(page).to have_content(evaluation_criterion_1.name)
      expect(page).to have_content(evaluation_criterion_2.name)
      expect(page).to have_button("Save grades", disabled: true)
    end

    scenario 'coach evaluates a pending submission and gives a feedback', js: true do
      sign_in_user coach.user, referer: review_course_path(course)

      expect(page).to have_content(target.title)
      expect(page).to have_content(target_2.title)

      find("a[aria-label='Submission #{submission_pending.id}']").click

      expect(page).to have_content('Grade Card')
      feedback = Faker::Markdown.sandwich(sentences: 6)
      add_markdown(feedback)
      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
        expect(page).to have_selector('.course-review-grade-card__grade-pill', count: 4)
        find("div[title='Bad']").click
      end

      # status should be reviewing as the target is not graded completely
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Reviewing')
      end
      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
        expect(page).to have_selector('.course-review-grade-card__grade-pill', count: 3)
        find("div[title='Bad']").click
      end

      # the status should be failed
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Failed')
      end

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
        find("div[title='Good']").click
      end

      # the status should be failed
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Failed')
      end

      click_button 'Save grades & send feedback'

      dismiss_notification

      expect(page).to have_button('Undo Grading')

      submission = submission_pending.reload
      expect(submission.evaluator_id).to eq(coach.id)
      expect(submission.passed_at).to eq(nil)
      expect(submission.evaluated_at).not_to eq(nil)
      expect(submission.startup_feedback.count).to eq(1)
      expect(submission.startup_feedback.last.feedback).to eq(feedback.strip)
      expect(submission.timeline_event_grades.pluck(:grade)).to contain_exactly(1, 2)

      # the submission must be removed from the pending list

      find("div[aria-label='submissions-overlay-close']").click
      expect(page).to have_text(submission_pending_2.target.title)
      expect(page).to_not have_text(submission.target.title)
    end

    scenario 'coach generates feedback from review checklist', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_pending)

      # Checklist item 1
      checklist_title_1 = Faker::Lorem.sentence
      c1_result_0_title = Faker::Lorem.sentence
      c1_result_0_feedback = Faker::Markdown.sandwich(sentences: 3)
      c1_result_1_title = Faker::Lorem.sentence
      c1_result_1_feedback = Faker::Markdown.sandwich(sentences: 3)

      # Checklist item 2
      checklist_title_2 = Faker::Lorem.sentence
      c2_result_0_title = Faker::Lorem.sentence
      c2_result_0_feedback = Faker::Markdown.sandwich(sentences: 3)
      c2_result_1_title = Faker::Lorem.sentence
      c2_result_1_feedback = Faker::Markdown.sandwich(sentences: 3)

      expect(target.review_checklist).to eq([])

      click_button 'Create a review checklist'

      within("div[aria-label='checklist-item-0']") do
        fill_in 'checklist_title', with: checklist_title_1
        fill_in 'result_0_title', with: c1_result_0_title
        fill_in 'result_0_feedback', with: c1_result_0_feedback

        fill_in 'result_1_title', with: c1_result_1_title
        fill_in 'result_1_feedback', with: c1_result_1_feedback
      end

      click_button 'Add Checklist Item'

      within("div[aria-label='checklist-item-1']") do
        fill_in 'checklist_title', with: checklist_title_2
        fill_in 'result_0_title', with: c2_result_0_title
        fill_in 'result_0_feedback', with: c2_result_0_feedback
        click_button 'Add Result'
        fill_in 'result_1_title', with: c2_result_1_title
        fill_in 'result_1_feedback', with: c2_result_1_feedback
      end

      click_button 'Save Checklist'

      expect(page).to have_content('Edit Checklist')

      expect(target.reload.review_checklist).not_to eq([])

      # Reload Page
      visit timeline_event_path(submission_pending)

      within("div[aria-label='checklist-item-0']") do
        expect(page).to have_content(checklist_title_1)

        within("div[aria-label='result-item-0']") do
          expect(page).to have_content(c1_result_0_title)
          find("label", text: c1_result_0_title).click
        end

        within("div[aria-label='result-item-1']") do
          expect(page).to have_content(c1_result_1_title)
          find("label", text: c1_result_1_title).click
        end
      end

      within("div[aria-label='checklist-item-1']") do
        expect(page).to have_content(checklist_title_2)
        within("div[aria-label='result-item-0']") do
          expect(page).to have_content(c2_result_0_title)
          find("label", text: c2_result_0_title).click
        end

        within("div[aria-label='result-item-1']") do
          expect(page).to have_content(c2_result_1_title)
          find("label", text: c2_result_1_title).click
        end
      end

      click_button 'Generate Feedback'

      within("div[aria-label='feedback']") do
        expect(page).to have_content(c1_result_0_feedback)
        expect(page).to have_content(c1_result_1_feedback)
        expect(page).to have_content(c2_result_0_feedback)
      end

      click_button 'Edit Checklist'

      within("div[aria-label='checklist-item-1']") do
        within("div[aria-label='result-item-0']") do
          find("button[title='Remove checklist result']").click
        end
      end

      within("div[aria-label='checklist-item-1']") do
        find("button[title='Remove checklist item']").click
      end

      within("div[aria-label='checklist-item-0']") do
        find("button[title='Remove checklist item']").click
      end

      click_button 'Save Checklist'

      click_button 'Create a review checklist'
      expect(target.reload.review_checklist).to eq([])
    end

    scenario 'coach evaluates a pending submission and mark a checklist as incorrect', js: true do
      question_1 = Faker::Lorem.sentence
      question_2 = Faker::Lorem.sentence
      answer_1 = Faker::Lorem.sentence
      answer_2 = "https://example.org/invalidLink"
      checklist = [{ "kind" => Target::CHECKLIST_KIND_LONG_TEXT, "title" => question_1, "result" => answer_1, "status" => TimelineEvent::CHECKLIST_STATUS_NO_ANSWER }, { "kind" => Target::CHECKLIST_KIND_LINK, "title" => question_2, "result" => answer_2, "status" => TimelineEvent::CHECKLIST_STATUS_NO_ANSWER }]
      submission_pending.update!(checklist: checklist)

      sign_in_user coach.user, referer: timeline_event_path(submission_pending)

      within("div[aria-label='#{submission_pending.checklist.first['title']}']") do
        expect(page).to have_content(question_1)
        expect(page).to have_content(answer_1)
      end

      within("div[aria-label='#{submission_pending.checklist.last['title']}']") do
        expect(page).to have_content(question_2)
        expect(page).to have_content(answer_2)
        click_button 'Mark as incorrect'
        expect(page).to have_content('Incorrect')
      end

      expect(page).to have_content('Grade Card')

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
        find("div[title='Good']").click
      end

      # status should be reviewing as the target is not graded completely
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Reviewing')
      end
      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
        find("div[title='Good']").click
      end

      # the status should be failed
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
      end

      click_button 'Save grades'

      dismiss_notification

      within("div[aria-label='#{submission_pending.checklist.last['title']}']") do
        expect(page).to have_content('Incorrect')
      end

      expect(submission_pending.reload.checklist).to eq([{ "kind" => Target::CHECKLIST_KIND_LONG_TEXT, "title" => question_1, "result" => answer_1, "status" => TimelineEvent::CHECKLIST_STATUS_NO_ANSWER }, { "kind" => Target::CHECKLIST_KIND_LINK, "title" => question_2, "result" => answer_2, "status" => TimelineEvent::CHECKLIST_STATUS_FAILED }])

      click_button('Undo Grading')

      expect(page).to have_text("Add Your Feedback")

      expect(submission_pending.reload.checklist).to eq(checklist)
    end

    scenario 'coach evaluates a pending submission without giving a feedback', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_pending)

      expect(page).to have_content('Grade Card')

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
        find("div[title='Good']").click
      end

      # status should be reviewing as the target is not graded completely
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Reviewing')
      end
      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
        find("div[title='Good']").click
      end

      # the status should be failed
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
      end

      click_button 'Save grades'

      dismiss_notification

      expect(page).to have_button('Undo Grading')

      submission = submission_pending.reload
      expect(submission.evaluator_id).to eq(coach.id)
      expect(submission.passed_at).not_to eq(nil)
      expect(submission.evaluated_at).not_to eq(nil)
      expect(submission.startup_feedback.count).to eq(0)
      expect(submission.timeline_event_grades.pluck(:grade)).to eq([2, 2])
    end

    scenario 'student tries to access the submission show' do
      sign_in_user team.founders.first.user, referer: timeline_event_path(submission_pending)

      expect(page).to have_text("The page you were looking for doesn't exist!")
    end

    scenario 'school admin tries to access the submission show' do
      sign_in_user school_admin.user, referer: timeline_event_path(submission_pending)

      expect(page).to have_text("The page you were looking for doesn't exist!")
    end

    scenario 'coach is warned when a student has dropped out', js: true do
      team.update!(dropped_out_at: 1.day.ago)

      sign_in_user coach.user, referer: timeline_event_path(submission_pending)

      expect(page).to have_text('This submission is from a student whose access to the course has ended, or has dropped out.')
    end

    scenario "coach is warned when a student's access to course has ended", js: true do
      team.update!(access_ends_at: 1.day.ago)

      sign_in_user coach.user, referer: timeline_event_path(submission_pending)

      expect(page).to have_text('This submission is from a student whose access to the course has ended, or has dropped out.')
    end

    context 'when submission is from students who are now in different teams' do
      let(:another_team) { create :startup, level: level, dropped_out_at: 1.day.ago }

      before do
        submission_pending.founders << another_team.founders.first
      end

      scenario 'coach is warned when one student in the submission is inactive', js: true do
        sign_in_user coach.user, referer: timeline_event_path(submission_pending)

        expect(page).to have_text('This submission is linked to one or more students whose access to the course has ended, or have dropped out.')
      end
    end

    scenario 'coach leaves a note about a student', js: true do
      note = Faker::Lorem.sentence

      sign_in_user team_coach.user, referer: timeline_event_path(submission_pending)

      click_button 'Write a Note'
      add_markdown note, id: "note-for-submission-#{submission_pending.id}"

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
        find("div[title='Good']").click
      end

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
        find("div[title='Good']").click
      end

      click_button 'Save grades'
      dismiss_notification
      new_notes = CoachNote.where(note: note)

      expect(new_notes.count).to eq(1)
      expect(new_notes.first.student_id).to eq(student.id)
    end

    scenario 'coach leaves a note for a team submission', js: true do
      another_student = team.founders.where.not(id: student).first
      submission_pending.founders << another_student
      note = Faker::Lorem.sentence

      sign_in_user team_coach.user, referer: timeline_event_path(submission_pending)

      click_button 'Write a Note'
      add_markdown note, id: "note-for-submission-#{submission_pending.id}"

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
        find("div[title='Good']").click
      end

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
        find("div[title='Good']").click
      end

      click_button 'Save grades'
      dismiss_notification
      new_notes = CoachNote.where(note: note)

      expect(new_notes.count).to eq(2)
      expect(new_notes.pluck(:student_id)).to contain_exactly(student.id, another_student.id)
    end

    scenario 'coach opens the overlay for a submission after its status has changed in the DB', js: true do
      # Opening the overlay should reload data on index if it's different.
      sign_in_user coach.user, referer: review_course_path(course)

      expect(page).to have_text(target.title)
      expect(page).to have_text(target_2.title)

      # Review the submission from the backend.
      submission_pending.update(passed_at: Time.zone.now, evaluated_at: Time.zone.now, evaluator: coach)
      grade_submission(submission_pending, SubmissionsHelper::GRADE_PASS, target)

      # Open the overlay.
      find("a[aria-label='Submission #{submission_pending.id}']").click

      # It should show passed.
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
      end

      find("div[aria-label='submissions-overlay-close']").click

      # Closing the overlay should show that the item has been removed from the pending list.
      expect(page).not_to have_text(target.title)
      expect(page).to have_text(target_2.title) # The second submission should still be there.

      # The submission should be visible in the Pending list.
      click_button 'Reviewed'

      # The submission should show up in the Reviewed list.
      expect(page).to have_text(target.title)

      # Undo the grading of the submission from the backend.
      submission_pending.timeline_event_grades.destroy_all
      submission_pending.update(passed_at: nil, evaluated_at: nil, evaluator: nil)

      find("a[aria-label='Submission #{submission_pending.id}']").click

      # The overlay should show pending review status.
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Not Reviewed')
      end

      find("div[aria-label='submissions-overlay-close']").click

      # Closing the overlay should show that the item has been removed from the reviewed list.
      expect(page).not_to have_text(target.title)
    end
  end

  context 'with a reviewed submission' do
    let(:submission_reviewed) { create(:timeline_event, latest: true, target: target, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }
    let!(:timeline_event_grade) { create(:timeline_event_grade, timeline_event: submission_reviewed, evaluation_criterion: evaluation_criterion_1) }

    before do
      submission_reviewed.founders << team.founders
    end

    scenario 'coach visits submission show', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_reviewed)

      within("div[aria-label='submissions-overlay-header']") do
        expect(page).to have_content('Level 1')
        expect(page).to have_content("Submitted by")

        # Each name should be linked to the report page.
        team.founders.each do |student|
          expect(page).to have_link(student.name, href: "/students/#{student.id}/report")
        end

        expect(page).to have_link(target.title, href: "/targets/#{target.id}")
      end

      expect(page).to have_content('Submission #1')
      expect(page).to have_content('Passed')

      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
        expect(page).to have_text('Evaluated By')
        expect(page).to have_text(coach.name)
        expect(page).to have_button("Undo Grading")
      end

      within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
        expect(page).to have_text(evaluation_criterion_1.name)
        expect(page).to have_text("#{timeline_event_grade.grade}/#{evaluation_criterion_1.max_grade}")
      end

      expect(page).to have_button("Add feedback")
    end

    scenario 'coach add his feedback', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_reviewed)

      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
        expect(page).to have_text('Evaluated By')
        expect(page).to have_text(coach.name)
        expect(page).to have_button("Undo Grading")
      end

      expect(page).to have_button("Add feedback")

      click_button "Add feedback"

      expect(page).not_to have_button("Add feedback")
      expect(page).to have_button("Share Feedback", disabled: true)

      feedback = Faker::Markdown.sandwich(sentences: 6)
      add_markdown(feedback)
      click_button "Share Feedback"

      dismiss_notification

      expect(page).to have_button('Add another feedback')

      within("div[aria-label='feedback-section']") do
        expect(page).to have_text(coach.name)
      end

      submission = submission_reviewed.reload
      expect(submission.startup_feedback.count).to eq(1)
      expect(submission.startup_feedback.last.feedback).to eq(feedback)
    end

    scenario 'coach can undo grading', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_reviewed)

      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
        expect(page).to have_text('Evaluated By')
        expect(page).to have_text(coach.name)
        expect(page).to have_button("Undo Grading")
      end

      click_button "Undo Grading"

      expect(page).to have_text("Add Your Feedback")

      submission = submission_reviewed.reload
      expect(submission.evaluator_id).to eq(nil)
      expect(submission.passed_at).to eq(nil)
      expect(submission.evaluated_at).to eq(nil)
      expect(submission.timeline_event_grades).to eq([])
    end
  end

  context 'Evaluation criteria changed for a target with graded submissions' do
    let(:target_1) { create :target, :for_founders, target_group: target_group }
    let(:submission_reviewed) { create(:timeline_event, latest: true, target: target_1, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }
    let!(:timeline_event_grade_1) { create(:timeline_event_grade, timeline_event: submission_reviewed, evaluation_criterion: evaluation_criterion_1) }
    let!(:timeline_event_grade_2) { create(:timeline_event_grade, timeline_event: submission_reviewed, evaluation_criterion: evaluation_criterion_2) }
    let(:submission_pending) { create(:timeline_event, latest: true, target: target_1) }

    before do
      submission_pending.founders << team.founders.first
      submission_reviewed.founders << team.founders.first
      target_1.evaluation_criteria << [evaluation_criterion_1]
    end

    scenario 'coach visits a submission', js: true do
      sign_in_user coach.user, referer: timeline_event_path(submission_reviewed)

      within("div[aria-label='submissions-overlay-card-#{submission_reviewed.id}']") do
        # Evaluation criteria at the point of grading are shown for reviewed submissions
        within("div[aria-label='evaluation-criterion-#{evaluation_criterion_1.id}']") do
          expect(page).to have_text(evaluation_criterion_1.name)
          expect(page).to have_text("#{timeline_event_grade_1.grade}/#{evaluation_criterion_1.max_grade}")
        end

        within("div[aria-label='evaluation-criterion-#{evaluation_criterion_2.id}']") do
          expect(page).to have_text(evaluation_criterion_2.name)
          expect(page).to have_text("#{timeline_event_grade_2.grade}/#{evaluation_criterion_2.max_grade}")
        end
      end

      within("div[aria-label='submissions-overlay-card-#{submission_pending.id}']") do
        # New list of evaluation criteria are shown for pending submissions
        expect(page).to have_text(evaluation_criterion_1.name)
        expect(page).not_to have_text(evaluation_criterion_2.name)
      end
    end
  end

  context 'with a reviewed submission that has feedback' do
    let(:submission_reviewed) { create(:timeline_event, latest: true, target: target, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }
    let(:feedback) { create(:startup_feedback, startup_id: team.id, faculty_id: coach.id) }
    let!(:timeline_event_grade) { create(:timeline_event_grade, timeline_event: submission_reviewed, evaluation_criterion: evaluation_criterion_1) }
    before do
      submission_reviewed.founders << team.founders.first
      submission_reviewed.startup_feedback << feedback
    end

    scenario 'team coach add his feedback', js: true do
      sign_in_user team_coach.user, referer: timeline_event_path(submission_reviewed)
      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
        expect(page).to have_text('Evaluated By')
        expect(page).to have_text(coach.name)
        expect(page).to have_button("Undo Grading")
      end
      within("div[aria-label='feedback-section']") do
        expect(page).to have_text(coach.name)
      end

      expect(page).to have_button("Add another feedback")
      click_button "Add another feedback"
      expect(page).not_to have_button("Add feedback")
      expect(page).to have_button("Share Feedback", disabled: true)

      feedback = Faker::Markdown.sandwich(sentences: 6)
      add_markdown(feedback)
      click_button "Share Feedback"

      dismiss_notification

      expect(page).to have_button('Add another feedback')

      submission = submission_reviewed.reload
      expect(submission.startup_feedback.count).to eq(2)
      expect(submission.startup_feedback.last.feedback).to eq(feedback)
    end

    scenario 'team coach undo submission', js: true do
      sign_in_user team_coach.user, referer: timeline_event_path(submission_reviewed)

      within("div[aria-label='submission-status']") do
        expect(page).to have_text('Passed')
        expect(page).to have_text('Evaluated By')
        expect(page).to have_text(coach.name)
        expect(page).to have_button("Undo Grading")
      end
      click_button "Undo Grading"

      expect(page).to have_text("Add Your Feedback")

      submission = submission_reviewed.reload
      expect(submission.evaluator_id).to eq(nil)
      expect(submission.passed_at).to eq(nil)
      expect(submission.evaluated_at).to eq(nil)
      expect(submission.timeline_event_grades).to eq([])
    end
  end

  context 'with a auto verified submission' do
    let(:auto_verified_submission) { create(:timeline_event, latest: true, target: auto_verify_target, passed_at: 1.day.ago) }
    before do
      auto_verified_submission.founders << team.founders.first
    end

    scenario 'coach visits submission show' do
      sign_in_user team_coach.user, referer: timeline_event_path(auto_verified_submission)

      expect(page).to have_text("The page you were looking for doesn't exist!")
    end
  end

  context 'with reviewed submissions from 2 teams' do
    let(:target) { create :target, :for_team, target_group: target_group }

    let(:submission_reviewed_1) { create(:timeline_event, latest: true, target: target, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }
    let(:submission_reviewed_2) { create(:timeline_event, latest: true, target: target, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }
    let(:submission_reviewed_3) { create(:timeline_event, latest: true, target: target, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }
    let(:submission_reviewed_4) { create(:timeline_event, latest: true, target: target, evaluator_id: coach.id, evaluated_at: 1.day.ago, passed_at: 1.day.ago) }

    let(:team_1) { create :startup, level: level }
    let(:team_2) { create :startup, level: level }

    let!(:timeline_event_grade_1) { create(:timeline_event_grade, timeline_event: submission_reviewed_1, evaluation_criterion: evaluation_criterion_1) }
    let!(:timeline_event_grade_2) { create(:timeline_event_grade, timeline_event: submission_reviewed_2, evaluation_criterion: evaluation_criterion_1) }
    let!(:timeline_event_grade_3) { create(:timeline_event_grade, timeline_event: submission_reviewed_3, evaluation_criterion: evaluation_criterion_1) }
    let!(:timeline_event_grade_4) { create(:timeline_event_grade, timeline_event: submission_reviewed_4, evaluation_criterion: evaluation_criterion_1) }

    before do
      submission_reviewed_1.founders << team_1.founders
      submission_reviewed_1.founders << team_2.founders.first

      submission_reviewed_2.founders << team_1.founders
      submission_reviewed_2.founders << team_2.founders

      submission_reviewed_3.founders << team_1.founders
      submission_reviewed_3.founders << team_2.founders
    end

    scenario 'coach visits submission show', js: true do
      sign_in_user team_coach.user, referer: timeline_event_path(submission_reviewed_1)

      # submission 1
      expect(page).to have_text(submission_reviewed_1.checklist.first['title'])
      expect(page).to have_text(team_1.founders.last.name)
      expect(page).to have_text(team_2.founders.first.name)
      expect(page).not_to have_text(submission_reviewed_2.checklist.first['title'])
      expect(page).not_to have_text(submission_reviewed_3.checklist.first['title'])

      # submission 2 and 3
      visit timeline_event_path(submission_reviewed_3)

      expect(page).to have_text(team_1.founders.last.name)
      expect(page).to have_text(team_2.founders.first.name)
      expect(page).to have_text(submission_reviewed_3.checklist.first['title'])
      expect(page).to have_text(submission_reviewed_2.checklist.first['title'])
      expect(page).not_to have_text(submission_reviewed_1.checklist.first['title'])
    end
  end
end
