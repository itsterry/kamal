require "test_helper"

class SshkitHostToSTest < ActiveSupport::TestCase
  test "host without port returns hostname only" do
    host = SSHKit::Host.new("1.1.1.1")
    assert_equal "1.1.1.1", host.to_s
  end

  test "host with port returns hostname:port" do
    host = SSHKit::Host.new("1.1.1.1:2222")
    assert_equal "1.1.1.1:2222", host.to_s
    assert_equal "1.1.1.1", host.hostname
    assert_equal 2222, host.port
  end

  test "host with user and port returns hostname:port" do
    host = SSHKit::Host.new("user@1.1.1.1:2222")
    assert_equal "1.1.1.1:2222", host.to_s
    assert_equal "user", host.username
    assert_equal "1.1.1.1", host.hostname
    assert_equal 2222, host.port
  end

  test "host with standard port returns hostname only" do
    host = SSHKit::Host.new("1.1.1.1:22")
    assert_equal "1.1.1.1", host.to_s
  end
end

class SshkitDnsRetryTest < ActiveSupport::TestCase
  setup do
    SSHKit::Backend::Netssh.configure { |config| config.dns_retries = 2 }
    @previous_output = SSHKit.config.output
    @log_io = StringIO.new
    SSHKit.config.output = Logger.new(@log_io)
  end

  teardown do
    SSHKit.config.output = @previous_output
  end

  test "retries dns errors" do
    attempts = 0

    result = SSHKit::Backend::Netssh.with_dns_retry("example.com") do
      attempts += 1
      raise SocketError, "getaddrinfo: Temporary failure in name resolution" if attempts < 3
      :ok
    end

    assert_equal 3, attempts
    assert_equal :ok, result
  end

  test "does not retry non dns errors" do
    attempts = 0

    assert_raises Errno::ECONNREFUSED do
      SSHKit::Backend::Netssh.with_dns_retry("example.com") do
        attempts += 1
        raise Errno::ECONNREFUSED
      end
    end

    assert_equal 1, attempts
  end

  test "netssh backend retries dns errors when connecting" do
    host = SSHKit::Host.new("unknown.example.com")
    backend = SSHKit::Backend::Netssh.new(host)

    SSHKit::Backend::Netssh.stubs(:sleep) # avoid actual backoff wait
    Net::SSH.expects(:start).twice.raises(SocketError, "getaddrinfo: nodename nor servname provided, or not known").then.returns(:ok)

    assert_equal :ok, backend.send(:connect_ssh, host.hostname, host.username, host.netssh_options)

    assert_includes @log_io.string, "Retrying DNS for #{host.hostname}"
  end
end
