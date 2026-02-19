require "test_helper"

class LivelineTestPageTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
  end

  test "liveline page renders chart shell and command bar controls" do
    get "/liveline"

    assert_response :success
    assert_includes response.body, 'id="liveline-test"'
    assert_includes response.body, 'id="liveline-test-chart"'
    assert_includes response.body, 'data-liveline-controls'
    assert_includes response.body, 'name="momentum"'
    assert_includes response.body, 'name="orderbook"'
    assert_includes response.body, 'data-liveline-metric="latest-value"'
    assert_includes response.body, 'import "liveline_test"'
  end

  test "legacy liveline-test route redirects" do
    get "/liveline-test"

    assert_response :redirect
    assert_redirected_to "/liveline"
  end
end
