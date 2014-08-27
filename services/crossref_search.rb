require 'cedilla/service'

# -------------------------------------------------------------------------
# An Implementation of the CedillaService Gem
#
# Would likely sit in another file within the project
# -------------------------------------------------------------------------
class CrossrefSearchService < Cedilla::Service
 
  # -------------------------------------------------------------------------
  def validate_citation(citation)
    ret = false
    
    # If the citation has an identifier OR it has a title for its respective genre then its valid
    if citation.is_a?(Cedilla::Citation)
      ret = (!citation.issn.nil? or !citation.eissn.nil? or !citation.doi.nil? or !citation.pmid.nil?)
      
      ret = (!citation.article_title.nil? and citation.genre == 'article') unless ret
    end
    
    LOGGER.debug "CROSSREF SEARCH - Checking validity of Citation (must have ISSN, DOI or PMID OR have an article title) -> #{ret}"
    
    ret
  end
  
  # -------------------------------------------------------------------------
  # All CoverThing cares about is the ISBN, so overriding the base class
  # -------------------------------------------------------------------------
  def add_citation_to_target(citation)
    # Record the citation for leter reference
    @citation = citation
    
    # Use one of the serial identifiers
    query = citation.doi unless citation.doi.nil?
    query = citation.pmid if !citation.pmid.nil? and query.nil?
    query = citation.eissn if !citation.eissn.nil? and query.nil?
    query = citation.issn if !citation.issn.nil? and query.nil?
    
    # No identifier was available so use the title
    query = citation.article_title if !citation.article_title.nil? and query.nil?
    
    targ = "#{build_target}#{URI.escape(query)}#{@config['sort_param']}"
    
    LOGGER.debug "CROSSREF SEARCH - Target after add_citation_to_target: #{targ}"
    
    targ
  end
  
  # -------------------------------------------------------------------------
  # Each implementation of a CedillaService MUST override this method!
  # -------------------------------------------------------------------------
  def process_response    
    LOGGER.debug "CROSSREF SEARCH - Response from target: #{@response_status}"
    #LOGGER.debug "CROSSREF SEARCH - Headers: #{@response_headers.collect{ |k,v| "#{k} = #{v}" }.join(', ')}"
    #LOGGER.debug "CROSSREF SEARCH - Body:"
    #LOGGER.debug @response_body
    
    ret = Cedilla::Citation.new({})
    
    json = JSON.parse(@response_body)
    
    json.first.each do |key,value|
      if key == 'doi'
        ret.doi = value if @citation.doi.nil?
        
      elsif key == 'title'
        ret.article_title = value if @citation.article_title.nil?
        
      elsif key == 'coins'
        # Call back to cedilla for a translation of the COINS OpenUrl
        url = URI.parse("#{@config['cedilla_citation_target']}?#{CGI.unescapeHTML(value)}")
    
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true if url.scheme == 'https'
    
        response = http.start do |http|
          http.open_timeout = @http_timeout
          http.read_timeout = @http_timeout
      
          http.get(url.request_uri, {}) 
        end
        
        # Since we just had the citation generated by the cedilla openurl service, add a stub request wrapper around the citation
        # and pass it to the Translator
        request = Cedilla::Translator.from_cedilla_json('{"citation":' + response.body.to_s + '}')
        
        request.citation.methods.each do |method|
          # If this is a setter (but not the equality test)
          if method.id2name[-1] == '=' and !method.id2name.include?('==')
            getter = method.id2name.sub('=', '')
            setter = method.id2name
            
            # Skip it if the value is empty!
            unless request.citation.method(getter).call.nil?
              # If the original citation responds to the setter
              if @citation.respond_to?(setter)
                # If this is the authors array check each author
                if getter == "authors"
                  request.citation.authors.each do |author|
                    ret.authors << author unless @citation.has_author?(author)
                  end
                
                # Otherwise set the response value if the original did not contain the value
                else
                  ret.method(setter).call(request.citation.method(getter).call) if @citation.method(getter).call.nil?
                end
              end
            end
          end
        end

      end
    end
    
    ret
  end
  
end
