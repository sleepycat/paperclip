module Paperclip
  module Storage
#This module is the lovechild of a late night cut and paste union of 
#Kyle Slattery's SFTP module and the credential handling portion of the S3 module
#all merged with the latest verion of paperclip.
#
#create your credentials file somewhere like config/sftp.yml:

#development:
#  sftp_host: somesite.com
#  sftp_user: someuser
#  sftp_password: somepassword
#production:
#  sftp_host: somesite.com
#  sftp_user: someuser
#  sftp_password: somepassword
#test:
#  sftp_host: somesite.com
#  sftp_user: someuser
#  sftp_password: somepassword
#
#Make sure you have the following gems in your Gemfile:
#gem 'net-ssh'
#gem 'net-sftp'

#Additionally you will need to make sure the user identifed in the 
#credentials has SSH access to the site you are pointing to. 
#As you can see below in the module there are a few calls that use SSH
# in there with the SFTP stuff.

#Then add the standard Paperclip stuff to your model. Note that :sftp_credentials is pointing
# to config/sftp.yml, which is where I stored my credentials.

# has_attached_file :poster, :storage => :sftp, :path => 'paperclipcache.com/capoeiraottawa.ca/:class/:style/:basename.:extension', :url => 'http://paperclipcache.com/capoeiraottawa.ca/:class/:style/:basename.:extension', :sftp_credentials => Rails.root.join("config", "sftp.yml").to_s, :styles => { :medium => { :geometry => "596x596>"}, :thumb => { :geometry => "150x150>" }}

#Kyle (http://kyleslattery.com) 


module Sftp
  def self.extended(base)
    require 'net/ssh'
    require 'net/sftp'
    
    base.instance_eval do
      @sftp_credentials = parse_credentials(@options[:sftp_credentials])
      @host = @sftp_credentials[:sftp_host]
      @user = @sftp_credentials[:sftp_user]
      @password = @sftp_credentials[:sftp_password]
    end
  end
  
  def parse_credentials creds
    creds = find_credentials(creds).stringify_keys
    (creds[Rails.env] || creds).symbolize_keys
  end

  def find_credentials creds
    case creds
    when File
      YAML::load(ERB.new(File.read(creds.path)).result)
    when String, Pathname
      YAML::load(ERB.new(File.read(creds)).result)
    when Hash
      creds
    else
      raise ArgumentError, "Credentials are not a path, file, or hash."
    end
  end

  private :find_credentials

  def ssh
  #TODO:change this to an SFTP connection if possible.
  #I don't see an equivalent to mkdir -p with sftp.
  #That might be why Kyle used SSH. 
    @ssh_connection ||= Net::SSH.start(@host, @user, :password => @password)
  end
  
  def exists?(style = default_style)
    ssh.exec!("ls #{path(style)} 2>/dev/null") ? true : false
  end
  
  def to_file(style=default_style)
    @queued_for_write[style] || (ssh.sftp.file.open(path(style), 'rb') if exists?(style))
  end
  alias_method :to_io, :to_file

  def flush_writes #:nodoc:
    Rails.logger.info("[paperclip] Writing files for #{name}")
    @queued_for_write.each do |style, file|
      file.close
      ssh.exec! "mkdir -p #{File.dirname(path(style))}"
      Rails.logger.info("[paperclip] -> #{path(style)}")
      ssh.sftp.upload!(file.path, path(style))
      ssh.sftp.setstat!(path(style), :permissions => 0644)
    end
    @queued_for_write = {}
  end

  def flush_deletes #:nodoc:
    Rails.logger.info("[paperclip] Deleting files for #{name}")
    @queued_for_delete.each do |path|
      begin
        Rails.logger.info("[paperclip] -> #{path}")
        ssh.sftp.remove!(path)
        FileUtils.rm(path) if File.exist?(path)
      rescue Net::SFTP::StatusException
        # ignore file-not-found, let everything else pass
      end
      begin
        while(path != '/')
          path = File.dirname(path)
          ssh.sftp.rmdir!(path)
        end
      rescue Net::SFTP::StatusException
        # Stop trying to remove parent directories
      end
    end
    @queued_for_delete = []
  end
end

end
end
