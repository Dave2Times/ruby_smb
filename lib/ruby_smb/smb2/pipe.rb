module RubySMB
  module SMB2
    # Represents a pipe on the Remote server that we can perform
    # various I/O operations on.
    class Pipe < File
      require 'ruby_smb/smb2/dcerpc'

      include RubySMB::SMB2::Dcerpc

      STATUS_CONNECTED = 0x00000003
      STATUS_CLOSING   = 0x00000004

      # Performs a peek operation on the named pipe
      #
      # @param peek_size [Integer] Amount of data to peek
      # @return [RubySMB::SMB2::Packet::IoctlResponse]
      # @raise [RubySMB::Error::InvalidPacket] if not a valid FSCTL_PIPE_PEEK response
      # @raise [RubySMB::Error::UnexpectedStatusCode] If status is not STATUS_BUFFER_OVERFLOW or STATUS_SUCCESS
      def peek(peek_size: 0)
        packet = RubySMB::SMB2::Packet::IoctlRequest.new
        packet.ctl_code = RubySMB::Fscc::ControlCodes::FSCTL_PIPE_PEEK
        packet.flags.is_fsctl = true
        # read at least 16 bytes for state, avail, msg_count, first_msg_len
        packet.max_output_response = 16 + peek_size
        packet = set_header_fields(packet)
        raw_response = @tree.client.send_recv(packet)
        begin
          response = RubySMB::SMB2::Packet::IoctlResponse.read(raw_response)
        rescue IOError
          response = RubySMB::SMB2::Packet::ErrorPacket.read(raw_response)
        end

        unless response.status_code == WindowsError::NTStatus::STATUS_BUFFER_OVERFLOW or response.status_code == WindowsError::NTStatus::STATUS_SUCCESS
          raise RubySMB::Error::UnexpectedStatusCode, response.status_code.name
        end

        unless response.smb2_header.command == RubySMB::SMB2::Commands::IOCTL
          raise RubySMB::Error::InvalidPacket, 'Not an IoctlResponse packet'
        end
        response
      end

      # @return [Integer] The number of bytes available to be read from the pipe
      def peek_available
        packet = peek
        state, avail, msg_count, first_msg_len = packet.buffer.unpack('VVVV')
        # Only 1 of these should be non-zero
        avail or first_msg_len
      end

      # @return [Integer] Pipe status
      def peek_state
        packet = peek
        packet.buffer.unpack('V')[0]
      end

      # @return [Boolean] True if pipe is connected, false otherwise
      def is_connected?
        begin
          state = peek_state
        rescue RubySMB::Error::UnexpectedStatusCode => e
          if e.message == 'STATUS_FILE_CLOSED'
            return false
          end
          raise e
        end
        state == STATUS_CONNECTED
      end

    end
  end
end
