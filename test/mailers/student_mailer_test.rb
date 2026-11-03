require "test_helper"

class StudentMailerTest < ActionMailer::TestCase
  test "welcome_email" do
    user = users(:one)
    temp_password = "TemporaryPass123!"

    mail = StudentMailer.welcome_email(user, temp_password)

    assert_equal "Welcome to TAG", mail.subject
    assert_equal [user.email], mail.to
    assert_equal ["toolassistedgradingadmin@gmail.com"], mail.from
    assert_match temp_password, mail.body.encoded
  end
end