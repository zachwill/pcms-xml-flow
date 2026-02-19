require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "at_least_role? uses role hierarchy" do
    viewer = users(:viewer)
    admin = users(:admin)

    assert viewer.at_least_role?(:viewer)
    assert_not viewer.at_least_role?(:analyst)

    assert admin.at_least_role?(:admin)
    assert admin.at_least_role?(:viewer)
  end
end
