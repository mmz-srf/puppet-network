require 'ipaddr'
require 'puppetx/filemapper'

Puppet::Type.type(:network_route).provide(:routes) do
  # Debian network_route routes provider.
  #
  # This provider uses the filemapper mixin to map the routes file to a
  # collection of network_route providers, and back.
  #
  # @see http://wiki.debian.org/NetworkConfiguration
  # @see http://packages.debian.org/squeeze/ifupdown-extras

  include PuppetX::FileMapper

  desc "Debian routes style provider"

  confine    :osfamily => :debian

  # $ dpkg -S /etc/network/if-up.d/20static-routes 
  # ifupdown-extra: /etc/network/if-up.d/20static-routes
  confine    :exists   => '/etc/network/if-up.d/20static-routes'

  defaultfor :osfamily => :debian

  has_feature :provider_options

  def select_file
    '/etc/network/routes'
  end

  def self.target_files
    ['/etc/network/routes']
  end

  class MalformedRoutesError < Puppet::Error
    def initialize(msg = nil)
      msg = 'Malformed debian routes file; cannot instantiate network_route resources' if msg.nil?
      super
    end
  end

  def self.raise_malformed
    @failed = true
    raise MalformedRoutesError
  end

  def self.parse_file(filename, contents)
    # Build out an empty hash for new routes for storing their configs.
    route_hash = Hash.new do |hash, key|
      hash[key] = {}
      hash[key][:name] = key
      hash[key]
    end

    lines = contents.split("\n")
    lines.each do |line|
      # Strip off any trailing comments
      line.sub!(/#.*$/, '')

      if line =~ /^\s*#|^\s*$/
        # Ignore comments and blank lines
        next
      end

      route = line.split

      if route.length < 4
        raise_malformed
      end

      # use the CIDR version of the target as :name
      cidr_target = "#{route[0]}/#{IPAddr.new(route[1]).to_i.to_s(2).count('1')}"

      route_hash[cidr_target][:name] = cidr_target
      route_hash[cidr_target][:network] = route[0]
      route_hash[cidr_target][:netmask] = route[1]
      route_hash[cidr_target][:gateway] = route[2]
      route_hash[cidr_target][:interface] = route[3]
    end

    route_hash.values
  end

  # Generate an array of sections
  def self.format_file(filename, providers)
    contents = {}
    contents['header'] = header

    # Build routes
    providers.sort_by(&:name).each do |provider|
      raise Puppet::Error, "#{provider.name} is missing the required parameter 'network'." if provider.network.nil?
      raise Puppet::Error, "#{provider.name} is missing the required parameter 'netmask'." if provider.netmask.nil?
      raise Puppet::Error, "#{provider.name} is missing the required parameter 'gateway'." if provider.gateway.nil?
      raise Puppet::Error, "#{provider.name} is missing the required parameter 'interface'." if provider.interface.nil?

      cidr_target = "#{provider.network}/#{IPAddr.new(provider.netmask).to_i.to_s(2).count('1')}"
      contents[cidr_target] = "#{provider.network} #{provider.netmask} #{provider.gateway} #{provider.interface}\n"
    end

    contents.values.join
  end

  def self.header
    str = <<-HEADER
# HEADER: This file is is being managed by puppet. Changes to
# HEADER: routes that are not being managed by puppet will persist;
# HEADER: however changes to routes that are being managed by puppet will
# HEADER: be overwritten. In addition, file order is NOT guaranteed.
# HEADER: Last generated at: #{Time.now}
HEADER
    str
  end
end
