require "rails_helper"

RSpec.describe "Rework Loop", type: :request do
  describe "TC-5.1: First rework regenerates draft" do
    xit "extracts instruction, regenerates draft, increments rework count" do
      # Preconditions: Email with status drafted, rework_count=0. User wrote
      #   "make it shorter" above the rework marker and applied Rework label.
      # Actions: Process a rework job
      # Expected:
      # - User instruction "make it shorter" extracted from draft
      # - Old draft trashed
      # - New draft generated with rework prompt
      # - New Gmail draft created
      # - "Rework" label removed, "Outbox" label added
      # - rework_count incremented to 1
      # - draft_reworked event logged with instruction
    end
  end

  describe "TC-5.2: Rework with no instruction uses default" do
    xit "uses default instruction when user provides none" do
      # Preconditions: User applied Rework label but didn't write any
      #   instructions above the marker.
      # Actions: Process a rework job
      # Expected:
      # - Instruction defaults to "(no specific instruction provided)"
      # - Draft still regenerated
    end
  end

  describe "TC-5.3: Third rework triggers limit" do
    xit "adds warning prefix and transitions to Action Required" do
      # Preconditions: Email with rework_count=2.
      # Actions: Process a rework job
      # Expected:
      # - Draft regenerated with warning prefix:
      #   "This is the last automatic rework..."
      # - Labels: Rework -> Action Required (not Outbox)
      # - Status remains drafted (rework_count=3)
    end
  end

  describe "TC-5.4: Fourth rework attempt hits hard limit" do
    xit "skips LLM call and moves to Action Required with skipped status" do
      # Preconditions: Email with rework_count=3 (already at limit).
      # Actions: Process a rework job
      # Expected:
      # - No LLM call made
      # - Labels: Rework -> Action Required
      # - Status set to skipped
      # - rework_limit_reached event logged
    end
  end
end
