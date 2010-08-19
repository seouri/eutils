require 'cgi'
require 'net/http'
require 'uri'
require 'nokogiri'
# Synopsis
# eutils = Eutils.new("medvane", "joon@medvane.org")
# eutils.einfo
class Eutils
  # Global constants
  # * host: http://http://eutils.ncbi.nlm.nih.gov
  # * EUTILS_INTERVAL
  EUTILS_HOST = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
  EUTILS_INTERVAL = 1.0 / 3.0
  @@last_access = nil
  @@last_access_mutex = nil

  attr_accessor :tool, :email

  def initialize(tool = nil, email = nil)
    @tool, @email = tool, email
  end

  # EInfo: Provides field index term counts, last update, and available links for each database.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/einfo_help.html
  def einfo(db = nil)
    db.strip! if db.class == String
    server = EUTILS_HOST + "einfo.fcgi"
    params = {"db" => db}
    response = post_eutils(server, params)
    if db.nil? || db.empty?
      return response.scan(/<DbName>(\w+)<\/DbName>/).flatten
    else
      return hash_from_response(response)  
    end
  end

  # ESearch: Searches and retrieves primary IDs (for use in EFetch, ELink, and ESummary) and term translations and optionally retains results for future use in the user's environment.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/esearch_help.html
  def esearch
    
  end

  # EPost: Posts a file containing a list of primary IDs for future use in the user's environment to use with subsequent search strategies.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/epost_help.html
  def epost
    
  end

  # ESummary: Retrieves document summaries from a list of primary IDs or from the user's environment.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/esummary_help.html
  def esummary
    
  end

  # EFetch: Retrieves records in the requested format from a list of one or more primary IDs or from the user's environment.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/efetch_help.html
  def efetch
    
  end

  # ELink: Checks for the existence of an external or Related Articles link from a list of one or more primary IDs.  Retrieves primary IDs and relevancy scores for links to Entrez databases or Related Articles;  creates a hyperlink to the primary LinkOut provider for a specific ID and database, or lists LinkOut URLs and Attributes for multiple IDs.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/elink_help.html
  def elink
    
  end

  # EGQuery: Provides Entrez database counts in XML for a single search using Global Query.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/egquery_help.html
  def egquery(term)
    term.strip! if term.class == String
    server = EUTILS_HOST + "egquery.fcgi"
    params = {"term" => term}
    response = post_eutils(server, params)
    return hash_from_response(response)
  end

  # ESpell: Retrieves spelling suggestions.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/espell_help.html
  def espell
    
  end

  private

  def post_eutils(server, params)
    check_tool_and_email
    ncbi_access_wait
    response = Net::HTTP.post_form(URI.parse(server), params)
    return response.body
  end

  # (Private) Sleeps until allowed to access. Adapted from BioRuby
  # ---
  # *Arguments*:
  # * (required) _wait_: wait unit time
  # *Returns*:: (undefined)
  def ncbi_access_wait(wait = EUTILS_INTERVAL)
    @@last_access_mutex ||= Mutex.new
    @@last_access_mutex.synchronize {
      if @@last_access
        duration = Time.now - @@last_access
        if wait > duration
          sleep wait - duration
        end
      end
      @@last_access = Time.now
    }
    nil
  end

  # (Private) Checks parameters as NCBI requires. Adapted from BioRuby
  # If no email or tool parameter, raises an error.
  #
  # NCBI announces that "Effective on
  # June 1, 2010, all E-utility requests, either using standard URLs or
  # SOAP, must contain non-null values for both the &tool and &email
  # parameters. Any E-utility request made after June 1, 2010 that does
  # not contain values for both parameters will return an error explaining
  # that these parameters must be included in E-utility requests."
  # ---
  # *Arguments*:
  # * (required) _opts_: Hash containing parameters
  # *Returns*:: (undefined)
  def check_tool_and_email
    if @email.to_s.empty? then
      raise 'Set email parameter for the query, or set eutils.email = "(your email address)"'
    end
    if @tool.to_s.empty? then
      raise 'Set tool parameter for the query, or set eutils.tool = "(your tool name)"'
    end
    nil
  end

  # Convert Nokogiri node to hash (adapted from http://gist.github.com/370755)
  def hash_from_response(response)
    node = Nokogiri::XML(response) {|cfg| cfg.noblanks.noent}
    return { node.root.name.to_sym => xml_node_to_hash(node.root) }
  end

  def xml_node_to_hash(node)
    return to_value(node.content.to_s) unless node.element?

    result_hash = {}

    node.attributes.each do |key, attr|
      ( result_hash[:attributes] ||= Hash.new )[attr.name.to_sym] = to_value(attr.value)
    end

    node.children.each do |child|
      result = xml_node_to_hash(child)

      if child.name == "text"
        return to_value(result) unless child.next_sibling || child.previous_sibling
      else
        key, val = child.name.to_sym, to_value(result)
        result_hash[key] = result_hash.key?(key) ? Array(result_hash[key]).push(val) : val
      end
    end

    result_hash
  end

  def to_value(data)
    data.is_a?(String) && data =~ /^\d+$/ ? data.to_i : data
  end
end