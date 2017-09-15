class StripGpgPassphrase < ActiveRecord::Migration
  def up
    if column_exists?(:lists, :gpg_passphrase)
      remove_column :lists, :gpg_passphrase
    end
  end

  def down
    add_column :lists, :gpg_passphrase, :string
  end
end
