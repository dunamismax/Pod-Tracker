require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "verify_email renders subject, recipient, and token link" do
    user = users(:two)
    email = UserMailer.verify_email(user)

    assert_equal "Verify your Ideal Magic email", email.subject
    assert_equal [ user.email_address ], email.to
    assert_match(/email_verifications/, email.body.encoded)
  end
end
