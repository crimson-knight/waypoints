require "http/client"
require "uri"
require "html"
require "llamero"
require "./store"

module Waypoints
  # Raised when a page cannot be fetched for description.
  class FetchError < Error
  end

  # Raised when the description model is unavailable or fails.
  class DescribeError < Error
  end

  # The structured description the model returns for a page. A BaseGrammar so
  # llamero can drive the local model toward exactly these fields; every
  # property carries a default, as llamero's schema generation requires.
  class BookmarkDescription < Llamero::BaseGrammar
    property title : String = ""
    property tags : Array(String) = [] of String
    property summary : String = ""

    # Builds a description directly (used by the heuristic fallback and specs).
    def initialize(@title : String = "", @tags : Array(String) = [] of String, @summary : String = "")
    end
  end

  # A fetched page reduced to the fields the describer reasons over.
  struct PageContent
    getter url : String
    getter title : String
    getter text : String

    # Builds page content from a URL and its extracted title and body text.
    def initialize(@url : String, @title : String, @text : String)
    end
  end

  # Seam over "fetch a URL into PageContent" so specs never touch the network.
  abstract class PageFetcher
    # Fetches *url* and returns its title and a trimmed text excerpt.
    abstract def fetch(url : String) : PageContent
  end

  # Fetches pages with the Crystal stdlib HTTP client: 10s timeouts, an
  # http->https upgrade, a small redirect follow, and <title>/body extraction.
  class HTTPPageFetcher < PageFetcher
    MAX_REDIRECTS =    5
    MAX_TEXT      = 4000

    # Builds a fetcher with a per-request connect/read timeout.
    def initialize(@timeout : Time::Span = 10.seconds)
    end

    # Fetches *url*, following a few redirects, and extracts its title and text.
    def fetch(url : String) : PageContent
      body = fetch_body(upgrade(url))
      PageContent.new(url, extract_title(body), extract_text(body))
    rescue ex : Socket::Error | IO::Error | URI::Error | ArgumentError
      raise FetchError.new("could not fetch #{url}: #{ex.message}")
    end

    # Upgrades a bare http:// URL to https:// so describe prefers TLS.
    private def upgrade(url : String) : String
      url.starts_with?("http://") ? url.sub("http://", "https://") : url
    end

    # Follows up to MAX_REDIRECTS 3xx responses and returns the final body.
    private def fetch_body(url : String) : String
      current = url
      MAX_REDIRECTS.times do
        uri = URI.parse(current)
        client = HTTP::Client.new(uri)
        client.connect_timeout = @timeout
        client.read_timeout = @timeout
        begin
          response = client.get(uri.request_target.presence || "/")
          if response.status.redirection? && (location = response.headers["Location"]?)
            current = URI.parse(location).absolute? ? location : uri.resolve(location).to_s
            next
          end
          return response.body
        ensure
          client.close
        end
      end
      raise FetchError.new("too many redirects fetching #{url}")
    end

    # Extracts and unescapes the first <title>, falling back to an empty string.
    private def extract_title(body : String) : String
      if match = body.match(/<title[^>]*>(.*?)<\/title>/im)
        HTML.unescape(match[1]).gsub(/\s+/, " ").strip
      else
        ""
      end
    end

    # Strips scripts, styles, and tags into a trimmed plain-text excerpt.
    private def extract_text(body : String) : String
      stripped = body
        .gsub(/<script\b[^>]*>.*?<\/script>/im, " ")
        .gsub(/<style\b[^>]*>.*?<\/style>/im, " ")
        .gsub(/<[^>]+>/, " ")
      HTML.unescape(stripped).gsub(/\s+/, " ").strip[0, MAX_TEXT]
    end
  end

  # Seam over the llamero piece describe needs: report whether real on-device
  # inference is available, and produce a structured description. Specs inject a
  # fake so the suite never loads MLX or downloads a model.
  abstract class DescriptionModel
    # True when backed by real native inference (vs. the deterministic mock).
    abstract def real? : Bool

    # Produces a structured description for *page*, or raises DescribeError.
    abstract def describe(page : PageContent) : BookmarkDescription
  end

  # Drives a local llamero model (Qwen3-0.6B-4bit by default) for descriptions.
  #
  # The runtime and session are built lazily so constructing this model is free
  # for callers that only inspect `real?`. On a machine without the built MLX
  # dylib, `Bridge.auto` selects the mock bridge and `real?` reports false, which
  # the describe flow uses to fall back to a heuristic rather than present mock
  # text as model output.
  class LlameroDescriptionModel < DescriptionModel
    DEFAULT_MODEL_ID = "mlx-community/Qwen3-0.6B-4bit"

    @runtime : Llamero::Native::MLXRuntime?
    @session : Llamero::Native::ModelSession?

    # Builds a model bound to *model_id* without touching the bridge yet.
    def initialize(@model_id : String = DEFAULT_MODEL_ID)
    end

    # True when the auto-selected bridge performs real Metal inference.
    def real? : Bool
      runtime.real_bridge?
    end

    # Asks the loaded model for a {title, tags, summary} description of *page*.
    def describe(page : PageContent) : BookmarkDescription
      messages = [
        Llamero::Message.system(
          "You describe web pages as concise bookmarks. Given a page's URL, " \
          "title, and text, respond with the page title, 2-5 short lowercase " \
          "topic tags, and a one-sentence summary."
        ),
        Llamero::Message.user("URL: #{page.url}\nTitle: #{page.title}\n\nPage text:\n#{page.text}"),
      ]
      response = session.chat_structured(messages, response_schema: BookmarkDescription)
      response.parsed || raise DescribeError.new("model returned no parseable description")
    rescue ex : Llamero::Native::NativeError
      # Surfaces ModelUnavailableError (and its HF_TOKEN guidance) as a clean error.
      raise DescribeError.new(ex.message || "llamero model unavailable")
    end

    private def runtime : Llamero::Native::MLXRuntime
      @runtime ||= Llamero::Native::MLXRuntime.new(model_id: @model_id)
    end

    private def session : Llamero::Native::ModelSession
      @session ||= begin
        built = runtime.start_session
        built.load_model
        built
      end
    end
  end

  # Coordinates a page fetch and a model (or heuristic) description, then saves
  # the resulting bookmark. Kept separate from the CLI so both are testable.
  class Describer
    # Builds a describer over a fetcher, a model seam, and diagnostic IO.
    def initialize(@fetcher : PageFetcher, @model : DescriptionModel, @diagnostics : IO = STDERR)
    end

    # Fetches *url*, describes it (model when real, heuristic otherwise), and
    # persists the bookmark in *store*, returning the saved record.
    def describe_and_save(url : String, store : Store) : Bookmark
      page = @fetcher.fetch(url)
      description = resolve(page)
      title = description.title.presence || page.title.presence || url
      store.add(url, title, description.tags, description.summary)
    end

    # Uses the real model when available; otherwise notes the degradation and
    # returns a deterministic heuristic so mock output is never sold as real.
    private def resolve(page : PageContent) : BookmarkDescription
      if @model.real?
        @model.describe(page)
      else
        @diagnostics.puts "(llamero mock bridge — heuristic description used)"
        Describer.heuristic(page)
      end
    end

    # Builds a description from the page itself: host-derived tag, title summary.
    def self.heuristic(page : PageContent) : BookmarkDescription
      BookmarkDescription.new(
        title: page.title.presence || page.url,
        tags: heuristic_tags(page.url),
        summary: page.title.presence || page.url
      )
    end

    # Derives a single lowercase tag from a URL's registrable host label.
    private def self.heuristic_tags(url : String) : Array(String)
      host = URI.parse(url).host
      return [] of String unless host

      labels = host.downcase.lchop("www.").split('.')
      label = labels.size >= 2 ? labels[-2] : labels.first
      label.empty? ? [] of String : [label]
    rescue
      [] of String
    end
  end
end
