require 'socket'
require 'openssl'
require 'json'

# Minimal HTTP/1.1 keep-alive server used to observe how many TCP connections a
# client really opens. Every accepted connection is served by its own thread
# and stays open until the client closes it (or the server is configured to
# drop it), which mirrors the behaviour of a real API server.
class LocalHttpServer
  Request = Struct.new(:method, :path, :query, :headers)

  attr_reader :port, :requests

  # +tls+:                  wrap the listener in TLS with a self-signed cert.
  # +drop_after_response+:  close the connection right after every response
  #                         without announcing it (simulates a server closing
  #                         idle keep-alive sockets under the client's feet).
  # +handler+:              block receiving a Request, returning [status, body];
  #                         for a 3xx status the body is used as the Location.
  def initialize(tls: false, drop_after_response: false, &handler)
    @tls = tls
    @drop_after_response = drop_after_response
    @handler = handler || ->(req) { [200, JSON.generate('path' => req.path, 'query' => req.query)] }
    @requests = []
    @accepted = 0
    @mutex = Mutex.new
    @client_threads = []
    @clients = []
  end

  def accepted_connections
    @mutex.synchronize { @accepted }
  end

  def start
    @tcp = TCPServer.new('127.0.0.1', 0)
    @port = @tcp.addr[1]
    @listener = @tls ? OpenSSL::SSL::SSLServer.new(@tcp, ssl_context) : @tcp
    @listener.start_immediately = true if @tls
    @acceptor = Thread.new { accept_loop }
    self
  end

  def stop
    @tcp.close rescue nil
    @acceptor.join(2) if @acceptor
    @mutex.synchronize { @clients.each { |c| c.close rescue nil } }
    @client_threads.each { |t| t.join(1) }
  end

  def url(path_and_query)
    "#{@tls ? 'https' : 'http'}://127.0.0.1:#{@port}#{path_and_query}"
  end

  private

  def accept_loop
    loop do
      begin
        socket = @listener.accept
      rescue IOError, Errno::EBADF, Errno::ECONNABORTED, OpenSSL::SSL::SSLError
        return if @tcp.closed?
        next
      end
      @mutex.synchronize do
        @accepted += 1
        @clients << socket
      end
      @client_threads << Thread.new(socket) { |s| serve(s) }
    end
  end

  def serve(socket)
    loop do
      request = read_request(socket)
      break unless request

      @mutex.synchronize { @requests << request }
      status, body = @handler.call(request)
      extra = ''
      if (300...400).cover?(status)
        extra = "Location: #{body}\r\n"
        body = ''
      end
      socket.write "HTTP/1.1 #{status} #{status == 200 ? 'OK' : 'ERROR'}\r\n" \
                   "Content-Type: application/json\r\n" \
                   "#{extra}" \
                   "Content-Length: #{body.bytesize}\r\n" \
                   "\r\n#{body}"
      socket.flush
      break if @drop_after_response || request.headers['connection'].to_s.casecmp('close').zero?
    end
  rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError, OpenSSL::SSL::SSLError
    # client went away
  ensure
    socket.close rescue nil
  end

  def read_request(socket)
    request_line = socket.gets
    return nil if request_line.nil?

    method, target = request_line.split(' ')
    path, query = target.split('?', 2)
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      name, value = line.chomp.split(':', 2)
      headers[name.downcase] = value.to_s.strip
    end
    socket.read(headers['content-length'].to_i) if headers['content-length']
    Request.new(method, path, query, headers)
  end

  def ssl_context
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new('SHA256'))

    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = cert
    ctx.key = key
    ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
    ctx
  end
end
