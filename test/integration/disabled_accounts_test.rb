require 'test_helper'

class DisabledAccountsTest < ActionDispatch::IntegrationTest
  setup do
    @authorization = FactoryGirl.create(:authorization)
    @user          = @authorization.user
    @article       = FactoryGirl.create(:article)
  end

  test "can log in normally when account is not disabled" do
    sign_user_in
    visit library_path
    
    assert_equal library_path, current_path
  end
  
  test "gets rerouted to session problem page when account is disabled" do
    @user.update_attribute(:account_disabled, true)
    sign_user_in
    visit articles_path
    
    assert_equal problems_sessions_path, current_path    
  end
end
