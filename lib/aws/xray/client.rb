require 'socket'

module Aws
  module Xray
    # Own the responsibility of holding destination address and sending
    # segments.
    class Client
      class << self
        # @param [Aws::Xray::Segment] segment
        def send_segment(segment)
          begin
            if Aws::Xray.config.client_options[:sock] # test env or not aws-xray is not enabled
              send_(segment)
            else # production env
              Worker.post(segment)
            end
          rescue QueueIsFullError => e
            begin
              host, port = Aws::Xray.config.client_options[:host], Aws::Xray.config.client_options[:port]
              Aws::Xray.config.segment_sending_error_handler.call(e, '', host: host, port: port)
            rescue Exception => e
              $stderr.puts("Error handler `#{Aws::Xray.config.segment_sending_error_handler}` raised an error: #{e}\n#{e.backtrace.join("\n")}")
            end
          end
        end

        # Will be called in other threads.
        # @param [Aws::Xray::Segment] segment
        def send_(segment)
          Aws::Xray.config.logger.debug("#{Thread.current}: Client#send_")
          payload = %!{"format": "json", "version": 1}\n#{segment.to_json}\n!

          sock = Aws::Xray.config.client_options[:sock] || UDPSocket.new
          host, port = Aws::Xray.config.client_options[:host], Aws::Xray.config.client_options[:port]

          begin
            len = sock.send(payload, Socket::MSG_DONTWAIT, host, port)
            raise CanNotSendAllByteError.new(payload.bytesize, len) if payload.bytesize != len
            Aws::Xray.config.logger.debug("#{Thread.current}: Client#send_ successfully sent payload, len=#{len}")
            len
          rescue SystemCallError, SocketError, CanNotSendAllByteError => e
            begin
              Aws::Xray.config.segment_sending_error_handler.call(e, payload, host: host, port: port)
            rescue Exception => e
              $stderr.puts("Error handler `#{Aws::Xray.config.segment_sending_error_handler}` raised an error: #{e}\n#{e.backtrace.join("\n")}")
            end
          ensure
            sock.close
          end
        end
      end
    end
  end
end
