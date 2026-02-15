require "rails_helper"

RSpec.describe User, type: :model do
  it { should validate_presence_of(:email) }
  it "validates uniqueness of email" do
    create(:user, email: "test@example.com")
    user = build(:user, email: "test@example.com")
    expect(user).not_to be_valid
  end
  it { should have_many(:emails).dependent(:destroy) }
  it { should have_many(:jobs).dependent(:destroy) }
  it { should have_one(:sync_state).dependent(:destroy) }

  describe ".active" do
    it "returns only active users" do
      active = create(:user, is_active: true)
      create(:user, is_active: false)
      expect(User.active).to eq([active])
    end
  end
end
