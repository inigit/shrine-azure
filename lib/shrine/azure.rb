require "shrine/azure/version"
require "azure/storage"

class Shrine
  module Storage
    class Azure
      attr_reader :client, :blobs, :container, :signer, :prefix, :cache_prefix

      # Cache prefix is using for copying from cache to store
      def initialize(storage_account_name, storage_access_key, container, prefix = '', cache_prefix = '')
        @client = ::Azure::Storage::Client.create(storage_account_name: storage_account_name, storage_access_key: storage_access_key)
        @signer = ::Azure::Storage::Core::Auth::SharedAccessSignature.new(storage_account_name, storage_access_key)
        @blobs = @client.blob_client
        @container = container
        @prefix = prefix
        @cache_prefix = cache_prefix
      end

      def upload(io, id, shrine_metadata: {}, **upload_options)
        # uploads `io` to the location `id`, can accept upload options
        begin
          if io.is_a?(UploadedFile)
            file = io.download
          elsif io.is_a?(Tempfile) || io.is_a?(File)
            file = io
          else
            file = io.tempfile
          end
          Rails.logger.info("[File]: #{file.inspect}")
          options = { :content_type => io.content_type,  content_disposition: 'attachment; filename=' + io.original_filename }
          if io.is_a?(UploadedFile)
            blobs.copy_blob(container + prefix, id, container, cache_prefix + '/' + io.data['id'] , options)
          else
            blobs.create_block_blob(container + prefix, id, IO.binread(file), options)
          end
        rescue Azure::Core::Http::HTTPError
          raise Shrine::Error
        end
      end

      def download(id, download: nil, &block)
      
      end

      def open(id, expires_in = nil, **options)
        # returns the remote file as an IO-like object
      end

      def url(id, expires_in = nil, **options)
        # options = { :content_type => io.metadata.mime_type,  content_disposition: 'attachment; filename=' + filename }

        generated_url = signer.signed_uri(
            uri_for(id), false,
            service: "b",
            permissions: "r",
            expiry: format_expiry(expires_in),

        ).to_s

        generated_url

      end

      def exists?(id)
        # returns whether the file exists on storage
        blob_for(key).present?
      end

      def delete(id)
        # deletes the file from the storage
        begin
          blobs.delete_blob(container, id)
        rescue Azure::Core::Http::HTTPError
          # Ignore files already deleted
        end
      end

      private

      def format_expiry(expires_in)
        expires_in ? Time.now.utc.advance(seconds: expires_in).iso8601 : nil
      end

      def uri_for(key)
        blobs.generate_uri("#{container}#{prefix}/#{key}")
      end

    end
  end
end
