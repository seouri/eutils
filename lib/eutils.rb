require 'cgi'
require 'net/http'
require 'uri'
require 'active_support/core_ext/hash/conversions'
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
  ActiveSupport::XmlMini.backend = "LibXMLSAX" # or "NokogiriSAX"

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
      return Hash.from_xml(response)["eInfoResult"]
    end
  end

  # ESearch: Searches and retrieves primary IDs (for use in EFetch, ELink, and ESummary) and term translations and optionally retains results for future use in the user's environment.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/esearch_help.html
  # eutils.esearch("autism")
  def esearch(term, db = "pubmed", params = {})
    term.strip! if term.class == String
    params["term"] = term
    params["db"] = db
    params["usehistory"] ||= "y"
    server = EUTILS_HOST + "esearch.fcgi"
    response = post_eutils(server, params)
    return Hash.from_xml(response)["eSearchResult"]
  end

  # EPost: Posts a file containing a list of primary IDs for future use in the user's environment to use with subsequent search strategies.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/epost_help.html
  # returns: webenv, querykey. Both nil for invalid epost.
  def epost(ids, db = "pubmed", params = {})
    params["id"] = ids.join(",")
    params["db"] = db
    server = EUTILS_HOST + "epost.fcgi"
    response = post_eutils(server, params)
    querykey = response.scan(/<QueryKey>(\d+)<\/QueryKey>/).flatten.first.to_i
    querykey = nil if querykey == 0
    webenv = response.scan(/<WebEnv>(\S+)<\/WebEnv>/).flatten.first
    return webenv, querykey
  end

  # ESummary: Retrieves document summaries from a list of primary IDs or from the user's environment.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/esummary_help.html
  def esummary(ids, db = "pubmed", params = {})
    params["id"] = ids.join(",")
    params["db"] = db
    server = EUTILS_HOST + "esummary.fcgi"
    response = post_eutils(server, params)
    return Hash.from_xml(response)["eSummaryResult"]
  end

  # EFetch: Retrieves records in the requested format from a list of one or more primary IDs or from the user's environment.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/efetch_help.html
  def efetch(db, webenv, query_key = 1, params = {})
    params["db"] = db
    params["WebEnv"] = webenv
    params["query_key"] = query_key
    params["retmode"] ||= "xml"
    params["retstart"] ||= 0
    params["retmax"] ||= 10
    server = EUTILS_HOST + "efetch.fcgi"
    response = post_eutils(server, params)
    if params["retmode"] == "xml"
      return Hash.from_xml(response)
    else
      return response
    end
  end

  # ELink: Checks for the existence of an external or Related Articles link from a list of one or more primary IDs.  Retrieves primary IDs and relevancy scores for links to Entrez databases or Related Articles;  creates a hyperlink to the primary LinkOut provider for a specific ID and database, or lists LinkOut URLs and Attributes for multiple IDs.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/elink_help.html
  def elink(ids, params = {})
    params["id"] = ids.join(",")
    params["cmd"] ||= "neighbor"
    params["dbfrom"] ||= "pubmed"
    params["db"] ||= "pubmed"
    params["retmode"] ||= "xml"
    server = EUTILS_HOST + "elink.fcgi"
    response = post_eutils(server, params)
    if params["retmode"] == "xml"
      return Hash.from_xml(response)["eLinkResult"]
    else
      return response
    end
  end

  # EGQuery: Provides Entrez database counts in XML for a single search using Global Query.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/egquery_help.html
  def egquery(term)
    term.strip! if term.class == String
    #server = EUTILS_HOST + "egquery.fcgi"
    server = "http://eutils.ncbi.nlm.nih.gov/gquery/"
    params = {"term" => term, "retmode" => "xml"}
    response = post_eutils(server, params)
    return Hash.from_xml(response)["Result"]
  end

  # ESpell: Retrieves spelling suggestions.
  # See also: http://eutils.ncbi.nlm.nih.gov/corehtml/query/static/espell_help.html
  def espell(term)
    term.strip! if term.class == String
    server = EUTILS_HOST + "espell.fcgi"
    params = {"db" => "pubmed", "term" => term}
    response = post_eutils(server, params)
    corrected = response.scan(/<CorrectedQuery>(.+)<\/CorrectedQuery>/).flatten.first.to_s
    corrected = term if corrected.empty?
    return corrected
  end

  private

  def post_eutils(server, params)
    check_tool_and_email
    ncbi_access_wait
    params["tool"] = tool
    params["email"] = email
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
end