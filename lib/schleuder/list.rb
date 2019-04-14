module Schleuder
  class List < ActiveRecord::Base

    has_many :subscriptions, dependent: :destroy
    before_destroy :delete_listdirs

    serialize :headers_to_meta, JSON
    serialize :bounces_drop_on_headers, JSON
    serialize :keywords_admin_notify, JSON

    validates :email, presence: true, uniqueness: true, email: true
    validates :fingerprint, presence: true, fingerprint: true
    validates :send_encrypted_only,
        :receive_encrypted_only,
        :receive_signed_only,
        :receive_authenticated_only,
        :receive_from_subscribed_emailaddresses_only,
        :receive_admin_only,
        :keep_msgid,
        :bounces_drop_all,
        :bounces_notify_admins,
        :include_list_headers,
        :include_openpgp_header,
        :forward_all_incoming_to_admins, boolean: true
    validates_each :headers_to_meta,
        :keywords_admin_notify do |record, attrib, value|
          value.each do |word|
            if word !~ /\A[a-z_-]+\z/i
              record.errors.add(attrib, I18n.t('errors.invalid_characters'))
            end
          end
        end
    validates_each :bounces_drop_on_headers do |record, attrib, value|
          value.each do |key, val|
            if key.to_s !~ /\A[a-z-]+\z/i || val.to_s !~ /\A[[:graph:]]+\z/i
              record.errors.add(attrib, I18n.t('errors.invalid_characters'))
            end
          end
        end
    validates :subject_prefix,
        :subject_prefix_in,
        :subject_prefix_out,
        no_line_breaks: true
    validates :openpgp_header_preference,
                presence: true,
                inclusion: {
                  in: %w(sign encrypt signencrypt unprotected none),
                }
    validates :max_message_size_kb, :logfiles_to_keep, greater_than_zero: true
    validates :log_level,
              presence: true,
              inclusion: {
                in: %w(debug info warn error),
              }
    validates :language,
              presence: true,
              inclusion: {
                # TODO: find out why we break translations and available_locales if we use I18n.available_locales here.
                in: %w(de en),
              }
    validates :public_footer, :internal_footer,
              allow_blank: true,
              format: {
                with: /\A[[:graph:]\s]*\z/i,
              }

    default_scope { order(:email) }

    def self.configurable_attributes
      @configurable_attributes ||= begin
        all = self.validators.map(&:attributes).flatten.uniq.compact.sort
        all - [:email, :fingerprint]
      end
    end

    def logfile
      @logfile ||= File.join(Conf.listlogs_dir, self.email.split('@').reverse, 'list.log')
    end

    def logger
      @logger ||= Listlogger.new(self)
    end

    def to_s
      email
    end

    def admins
      subscriptions.where(admin: true)
    end

    def key(fingerprint=self.fingerprint)
      keys(fingerprint).first
    end

    def secret_key
      keys(self.fingerprint, true).first
    end

    def keys(identifier=nil, secret_only=nil)
      gpg.find_keys(identifier, secret_only)
    end

    def import_key(importable)
      gpg.keyimport(importable)
    end

    def import_key_and_find_fingerprint(key_material)
      return nil if key_material.blank?

      import_result = import_key(key_material)
      gpg.interpret_import_result(import_result)
    end

    def delete_key(fingerprint)
      if key = keys(fingerprint).first
        key.delete!
        true
      else
        false
      end
    end

    def export_key(fingerprint=self.fingerprint)
      key = keys(fingerprint).first
      if key.blank?
        return false
      end
      key.armored
    end

    def check_keys
      now = Time.now
      checkdate = now + (60 * 60 * 24 * 14) # two weeks
      unusable = []
      expiring = []

      keys.each do |key|
        expiry = key.subkeys.first.expires
        if expiry && expiry > now && expiry < checkdate
          # key expires in the near future
          expdays = ((expiry - now)/86400).to_i
          expiring << [key, expdays]
        end

        if ! key.usable?
          unusable << [key, key.usability_issue]
        end
      end

      text = ''
      expiring.each do |key, days|
        text << I18n.t('key_expires', {
                          days: days,
                          key_oneline: key.oneline
                      })
        text << "\n"
      end

      unusable.each do |key, usability_issue|
        text << I18n.t('key_unusable', {
                          usability_issue: usability_issue,
                          key_oneline: key.oneline
                      })
        text << "\n"
      end
      text
    end

    def refresh_keys
      gpg.refresh_keys(self.keys)
    end

    def fetch_keys(input)
      gpg.fetch_key(input)
    end

    def self.by_recipient(recipient)
      listname = recipient.gsub(/-(sendkey|request|owner|bounce)@/, '@')
      where(email: listname).first
    end

    def sendkey_address
      @sendkey_address ||= email.gsub('@', '-sendkey@')
    end

    def request_address
      @request_address ||= email.gsub('@', '-request@')
    end

    def owner_address
      @owner_address ||= email.gsub('@', '-owner@')
    end

    def bounce_address
      @bounce_address ||= email.gsub('@', '-bounce@')
    end

    def gpg
      @gpg_ctx ||= begin
        # TODO: figure out why set it again...
        # Set GNUPGHOME when list is created.
        set_gnupg_home
        GPGME::Ctx.new armor: true
      end
    end

    # TODO: place this somewhere sensible.
    # Call cleanup when script finishes.
    #Signal.trap(0, proc { @list.cleanup })
    def cleanup
      if @gpg_agent_pid
        Process.kill('TERM', @gpg_agent_pid.to_i)
      end
    rescue => e
      $stderr.puts "Failed to kill gpg-agent: #{e}"
    end

    def gpg_sign_options
      {sign: true, sign_as: self.fingerprint}
    end

    def fingerprint=(arg)
      if arg
        write_attribute(:fingerprint, arg.gsub(/\s*/, '').gsub(/^0x/, '').chomp.upcase)
      end
    end

    def self.listdir(listname)
      File.join(
          Conf.lists_dir,
          listname.split('@').reverse
        )
    end

    def listdir
      @listdir ||= self.class.listdir(self.email)
    end

    # A convenience-method to simplify other code.
    def subscribe(email, fingerprint=nil, adminflag=nil, deliveryflag=nil, key_material=nil)
      messages = nil
      args = {
          list_id: self.id,
          email: email
      }
      if key_material.present?
        fingerprint, messages = import_key_and_find_fingerprint(key_material)
      end
      args[:fingerprint] = fingerprint
      # ActiveRecord does not treat nil as falsy for boolean columns, so we
      # have to avoid that in order to not receive an invalid object. The
      # database will use the column's default-value if no value is being
      # given. (I'd rather not duplicate the defaults here.)
      if ! adminflag.nil?
        args[:admin] = adminflag
      end
      if ! deliveryflag.nil?
        args[:delivery_enabled] = deliveryflag
      end
      subscription = Subscription.create(args)
      [subscription, messages]
    end

    def unsubscribe(email, delete_key=false)
      sub = subscriptions.where(email: email).first
      if sub.blank?
        false
      end

      if ! sub.destroy
        return sub
      end

      if delete_key
        sub.delete_key
      end
    end

    def keywords_admin_notify
      Array(read_attribute(:keywords_admin_notify))
    end

    def from_admin?(mail)
      return false if ! mail.was_validly_signed?
      admins.find do |admin|
        admin.fingerprint == mail.signing_key.fingerprint
      end.presence || false
    end

    def set_attribute(attrib, value)
      self.send("#{attrib}=", value)
    end

    def send_list_key_to_subscriptions
      mail = Mail.new
      mail.from = self.email
      mail.subject = I18n.t('list_public_key_subject')
      mail.body = I18n.t('list_public_key_attached')
      mail.attach_list_key!(self)
      send_to_subscriptions(mail)
      true
    end

    def send_to_subscriptions(mail)
      logger.debug 'Sending to subscriptions.'
      mail.add_internal_footer!
      self.subscriptions.each do |subscription|
        begin
          if subscription.delivery_enabled
            subscription.send_mail(mail)
          else
            logger.info "Not sending to #{subscription.email}: delivery is disabled."
          end
        rescue => exc
          msg = I18n.t('errors.delivery_error',
                       { email: subscription.email, error: exc.to_s })
          logger.error msg
          logger.error exc
        end
      end
    end

    private

    def set_gnupg_home
      ENV['GNUPGHOME'] = listdir
    end

    def delete_listdirs
      if File.exists?(self.listdir)
        FileUtils.rm_rf(self.listdir, secure: true)
        Schleuder.logger.info "Deleted #{self.listdir}"
      end
      # If listlogs_dir is different from lists_dir, the logfile still exists
      # and needs to be deleted, too.
      logfile_dir = File.dirname(self.logfile)
      if File.exists?(logfile_dir)
        FileUtils.rm_rf(logfile_dir, secure: true)
        Schleuder.logger.info "Deleted #{logfile_dir}"
      end
      true
    rescue => exc
      # Don't use list-logger here — if the list-dir isn't present we can't log to it!
      Schleuder.logger.error "Error while deleting listdir: #{exc}"
      return false
    end
  end
end
