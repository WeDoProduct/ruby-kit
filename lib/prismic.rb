require 'net/http'
require 'uri'

module Prismic

  # These exception can contains an error cause and is able to show them
  class Error < Exception
    attr_reader :cause
    def initialize(msg=nil, cause=nil)
      msg ? super(msg) : msg
      @cause = cause
    end
    def full_trace(e=self)
      first, *backtrace = e.backtrace
      msg = e == self ? "" : "Caused by "
      msg += "#{first}: #{e.message} (#{e.class})"
      stack = backtrace.map{|s| "\tfrom #{s}" }.join("\n")
      cause = e.respond_to?(:cause) ? e.cause : nil
      cause_stack = cause ? full_trace(cause) : nil
      [msg, stack, cause_stack].compact.join("\n")
    end
  end

  def self.api(*args)
    API.start(*args)
  end

  class ApiData
    attr_accessor :refs, :bookmarks, :types, :tags, :forms
  end

  class SearchForm
    attr_accessor :api, :form, :data, :ref

    def initialize(api, form, data={}, ref = nil)
      @api = api
      @form = form
      @data = form.default_data.merge(data)
      @ref = ref
    end

    def name
      form.name
    end

    def form_method
      form.form_method
    end

    def rel
      form.rel
    end

    def enctype
      form.enctype
    end

    def action
      form.action
    end

    def fields
      form.fields
    end

    def submit(ref = @ref)
      raise NoRefSetException if @ref == nil

      if form_method == "GET" && enctype == "application/x-www-form-urlencoded"
        data['ref'] = ref
        data.delete_if { |k, v| !v }

        uri = URI(action)
        uri.query = URI.encode_www_form(data)

        request_uri = uri.request_uri
        request_uri += (request_uri =~ /\?/ ? '&' : '?') + "access_token=#{api.access_token}" if api.access_token
        request = Net::HTTP::Get.new(request_uri)
        request.add_field('Accept', 'application/json')

        response = Net::HTTP.new(uri.host, uri.port).start do |http|
          http.request(request)
        end

        raise RefNotFoundException, "Ref #{ref} not found" if response.code == "404"

        raise FormSearchException, "Error : #{response.body}" if response.code != "200"

        JSON.parse(response.body).map do |doc|
          raise FormSearchException, "Error : #{doc['error']}" if doc.include?('error')
          Prismic::JsonParser.document_parser(doc)
        end
      else
        raise UnsupportedFormKind, "Unsupported kind of form: #{form_method} / #{enctype}"
      end
    end

    def query(query)
      strip_brakets = ->(str) { str =~ /^\[(.*)\]$/ ? $1 : str }
      previous_query = form.fields['q'] ? form.fields['q'].default.to_s : ''
      data['q'] = "[%s%s]" % [strip_brakets.(previous_query), strip_brakets.(query)]
      self
    end

    def set(field, value)
      form.set(field, value)
    end

    def ref(ref)
      @ref = ref
    end

    class NoRefSetException < Error ; end
    class UnsupportedFormKind < Error ; end
    class RefNotFoundException < Error ; end
    class FormSearchException < Error ; end
  end

  class Field
    attr_accessor :field_type, :default

    def initialize(field_type, default)
      @field_type = field_type
      @default = default
    end

  end

  class Document
    attr_accessor :id, :type, :href, :tags, :slugs, :fragments

    def initialize(id, type, href, tags, slugs, fragments)
      @id = id
      @type = type
      @href = href
      @tags = tags
      @slugs = slugs
      @fragments = (fragments.is_a? Hash) ? parse_fragments(fragments) : fragments
    end

    def slug
      slugs.empty? ? '-' : slugs.first
    end

    def as_html(link_resolver)
      fragments.map { |field, fragment|
        %(<section data-field="#{field}">#{fragment.as_html(link_resolver)}</section>)
      }.join("\n")
    end

    private

    def parse_fragments(fragments)
      fragments
    end
  end

  class Ref
    attr_accessor :ref, :label, :is_master, :scheduled_at

    def initialize(ref, label, is_master = false, scheduled_at = nil)
      @ref = ref
      @label = label
      @is_master = is_master
      @scheduled_at = scheduled_at
    end

    alias :master? :is_master
  end

  class LinkResolver
    attr_reader :ref
    def initialize(ref, &blk)
      @ref = ref
      @blk = blk
    end
    def link_to(doc_link)
      @blk.call(doc_link)
    end
  end

  def self.link_resolver(ref, &blk)
    LinkResolver.new(ref, &blk)
  end
end

require 'prismic/api'
require 'prismic/form'
require 'prismic/fragments'
require 'prismic/json_parsers'
