module Schleuder
  class Account < ActiveRecord::Base
    PASSWORD_CHARS = [
      ('a'..'z').to_a,
      ('A'..'Z').to_a,
      (0..9).to_a,
      %w[! @ # $ % ^ & * ( ) _ - + = { [ } ] : ; < , > . ? /]
    ].flatten
    PASSWORD_LENGTH_RANGE = (10..12).freeze

    has_secure_password

    has_many :subscriptions, foreign_key: 'email', primary_key: 'email'

    validates :email, presence: true, email: true, uniqueness: true, allow_nil: false
    validates :password, presence: true, allow_nil: false

    before_save { email.downcase! }

    def lists
      List.joins(:subscriptions).where(subscriptions: {email: email})
    end

    def admin_lists
      List.joins(:subscriptions).where(subscriptions: {email: email, admin: true})
    end

    def admin_list_subscriptions
      Subscription.where(list_id: admin_lists.pluck(:id))
    end

    def set_new_password!
      new_password = generate_password
      update!(password: new_password)
      new_password
    end

    def subscribed_to_list?(list)
      subscriptions.where(list_id: list.id).exists?
    end

    def admin_of_list?(list)
      list.admins.where(email: email).exists?
    end

    def authorize!(resource, action)
      authorizer.authorize!(resource, action)
    end

    def scoped(resource)
      authorizer.scoped(resource)
    end

    private

    def authorizer
      @authorizer ||= Authorizer.new(self)
    end

    def generate_password
      length = rand(PASSWORD_LENGTH_RANGE)
      PASSWORD_CHARS.shuffle.take(length).join
    end
  end
end