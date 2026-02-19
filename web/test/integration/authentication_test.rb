require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    @viewer = users(:viewer)
    @admin = users(:admin)
  end

  test "non-localhost requests are redirected to login" do
    host! "example.com"

    get "/salary-book", headers: modern_headers

    assert_redirected_to login_path
  end

  test "localhost bypasses authentication" do
    host! "localhost"

    get "/liveline", headers: modern_headers

    assert_response :success
  end

  test "viewer can sign in" do
    host! "example.com"

    post "/login", params: {
      email: @viewer.email,
      password: "password123"
    }, headers: modern_headers

    assert_redirected_to salary_book_path
  end

  test "viewer is blocked from admin-only route" do
    host! "example.com"
    sign_in_as(@viewer)

    get "/liveline", headers: modern_headers

    assert_redirected_to salary_book_path
  end

  test "admin can access admin-only route" do
    host! "example.com"
    sign_in_as(@admin)

    get "/liveline", headers: modern_headers

    assert_response :success
  end

  private

  def sign_in_as(user)
    post "/login", params: {
      email: user.email,
      password: "password123"
    }, headers: modern_headers

    assert_redirected_to salary_book_path
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
