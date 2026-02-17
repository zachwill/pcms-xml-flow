require "test_helper"

class LivelineTestPageTest < ActionDispatch::IntegrationTest
  test "liveline test page renders chart shell and controls" do
    get "/liveline-test"

    assert_response :success
    assert_includes response.body, 'id="liveline-test"'
    assert_includes response.body, 'id="liveline-test-chart"'
    assert_includes response.body, 'data-liveline-controls'
    assert_includes response.body, 'name="momentum"'
    assert_includes response.body, 'name="orderbook"'
    assert_includes response.body, 'data-liveline-metric="latest-value"'
    assert_includes response.body, 'import "liveline_test"'
  end
end
