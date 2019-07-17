class SchleuderApiDaemon < Sinatra::Base
  register Sinatra::Namespace

  namespace '/lists' do
    get '/:list_email/keys.json' do |list_email|
      keys = keys_controller.find_all(list_email)
      keys_hash = keys.sort_by(&:email).map do |key|
        key_hash = key_to_hash(key)
        if authorized_to_read_subscriptions?(list_email)
          subscription = subscription(list_email, key.fingerprint)
          if subscription
            key_hash.merge!(subscription: subscription.email)
          end
        end
        key_hash
      end
      json keys_hash
    end

    post '/:list_email/keys.json' do |list_email|
      input = parsed_body['keymaterial']
      if !input.match('BEGIN PGP')
        input = Base64.decode64(input)
      end
      json keys_controller.import(list_email, input)
    end

    get '/:list_email/keys/check.json' do |list_email|
      json result: keys_controller.check(list_email)
    end

    get '/:list_email/keys/:fingerprint.json' do |list_email, fingerprint|
      key = keys_controller.find(list_email, fingerprint)
      key_hash = key_to_hash(key, true)
      if authorized_to_read_subscriptions?(list_email)
        subscription = subscription(list_email, key.fingerprint)
        if subscription
          key_hash.merge!(subscription: subscription.email)
        end
      end
      json key_hash
    end

    delete '/:list_email/keys/:fingerprint.json' do |list_email, fingerprint|
      keys_controller.delete(list_email, fingerprint)
    end
  end

  private

  def keys_controller
    Schleuder::KeysController.new(current_account)
  end

  def lists_controller
    Schleuder::ListsController.new(current_account)
  end

  def subscriptions_controller
    Schleuder::SubscriptionsController.new(current_account)
  end

  def subscription(list_email, fingerprint)
    subscription = subscriptions_controller.find_all(list_email, {fingerprint: fingerprint}).first
    subscription ||= nil
  end
  
  def authorized_to_read_subscriptions?(list_email)
    list = lists_controller.find(list_email) 
    authorize!(list, :list_subscriptions)
    return true
  rescue Errors::Unauthorized
    return false
  end

  def key_to_hash(key, include_keydata=false)
    hash = {
      fingerprint: key.fingerprint,
      email: key.email,
      expiry: key.expires,
      generated_at: key.generated_at,
      primary_uid: key.primary_uid.uid,
      oneline: key.oneline,
      trust_issues: key.usability_issue,
    }
    if include_keydata
      hash[:description] = key.to_s
      hash[:ascii] = key.armored
    end
    hash
  end
end
