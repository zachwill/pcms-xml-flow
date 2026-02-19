# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

admin_email = ENV["WEB_ADMIN_EMAIL"].to_s.strip.downcase
admin_password = ENV["WEB_ADMIN_PASSWORD"].to_s

if admin_email.present? && admin_password.present?
  user = User.find_or_initialize_by(email: admin_email)
  user.role = "admin"
  user.password = admin_password
  user.save!
end
