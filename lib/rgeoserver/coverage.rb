
module RGeoServer
  # A coverage is a raster based data set which originates from a coverage store.
  class Coverage < ResourceInfo

    OBJ_ATTRIBUTES = {
      :catalog => "catalog", 
      :workspace => "workspace", 
      :coverage_store => "coverage_store", 
      :name => "name", 
      :title => "title", 
      :abstract => "abstract", 
      :keywords => "keywords", 
      :metadata => "metadata", 
      :metadata_links => "metadataLinks" 
    }
    OBJ_DEFAULT_ATTRIBUTES = {
      :catalog => nil, 
      :workspace => nil, 
      :coverage_store => nil, 
      :name => nil, 
      :title => nil, 
      :abstract => nil,  
      :keywords => [],  
      :metadata => {},  
      :metadata_links => [] 
    } 
   
    # see http://inspire.ec.europa.eu/schemas/common/1.0/common.xsd
    @@metadata_types = {
      'ISO19139' => 'application/vnd.iso.19139+xml',
      'TC211' => 'application/vnd.iso.19139+xml'
    }
   
    define_attribute_methods OBJ_ATTRIBUTES.keys
    update_attribute_accessors OBJ_ATTRIBUTES

    @@route = "workspaces/%s/coveragestores/%s/coverages"
    @@root  = "coverages"
    @@resource_name = "coverage"

    def self.root
      @@root
    end

    def self.member_xpath
      "//#{resource_name}"
    end

    def self.resource_name
      @@resource_name
    end

    def route
      @@route % [@workspace.name , @coverage_store.name]
    end

    def to_mimetype(type, default = 'text/xml')
      return @@metadata_types[type.upcase] if @@metadata_types.include?(type.upcase) 
      default
    end

    def message
      ap({ :CV_new => new?, :CV_keywords => @keywords, :CV_metadataLinks => @metadata_links})
      
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.coverage {
          xml.name @name
          xml.title @title 
          if new?
            xml.nativeName @name
            xml.abstract @abtract if abstract_changed?
            xml.keywords {
              @keywords.each do |k|
                if k.is_a? Hash
                  # Example: United States\@language=en\;\@vocabulary=ISOTC211/19115:place\;
                  k = "#{k[:keyword]}" +
                      (("\\@language=#{k[:language]}\\;" if k[:language])||"") +
                      (("\\@vocabulary=#{k[:vocabulary]}\\;" if k[:vocabulary])||"")
                end              
                xml.keyword k
              end
            } if @keywords

            xml.metadata {
              @metadata.each do |k,v|
                xml.send(k.to_s, v.to_s)
              end
            } if @metadata

            xml.metadataLinks {
              @metadata_links.each do |m|
                xml.metadataLink {
                  xml.type_ to_mimetype(m['metadataType'])
                  xml.metadataType m['metadataType']
                  xml.content m['content']
                }
              end
            } if @metadata_links
          end
        }
      end
      ap({ :message => builder.doc})
      
      @message = builder.doc.to_xml 
    end

    # @param [RGeoServer::Catalog] catalog
    # @param [Hash] options
    def initialize catalog, options 
      super({})
      _run_initialize_callbacks do
        @catalog = catalog
        workspace = options[:workspace] || 'default'
        if workspace.instance_of? String
          @workspace = @catalog.get_workspace(workspace)
        elsif workspace.instance_of? Workspace
          @workspace = workspace
        else
          raise "Not a valid workspace"
        end
        coverage_store = options[:coverage_store]
        if coverage_store.instance_of? String
          @coverage_store = CoverageStore.new @catalog, :workspace => @workspace, :name => coverage_store
        elsif coverage_store.instance_of? CoverageStore
          @coverage_store = coverage_store
        else
          raise "Not a valid coverage store"
        end

        @name = options[:name]
        @enabled = options[:enabled] || true
        @route = route
      end        
    end

    def profile_xml_to_hash profile_xml
      doc = profile_xml_to_ng profile_xml
      h = {
        "coverage_store" => @coverage_store.name,
        "workspace" => @workspace.name,
        "name" => doc.at_xpath('//name').text.strip,
        "nativeName" => doc.at_xpath('//nativeName/text()').to_s,
        "nativeCRS" => doc.at_xpath('//nativeCRS/text()').to_s,
        "title" => doc.at_xpath('//title/text()').to_s,
        "srs" => doc.at_xpath('//srs/text()').to_s,
        "nativeBoundingBox" => { 
          'minx' => doc.at_xpath('//nativeBoundingBox/minx/text()').to_s,
          'miny' => doc.at_xpath('//nativeBoundingBox/miny/text()').to_s,
          'maxx' => doc.at_xpath('//nativeBoundingBox/maxx/text()').to_s,
          'maxy' => doc.at_xpath('//nativeBoundingBox/maxy/text()').to_s,
          'crs' => doc.at_xpath('//nativeBoundingBox/crs/text()').to_s
        },
        "latLonBoundingBox" => { 
          'minx' => doc.at_xpath('//latLonBoundingBox/minx/text()').to_s,
          'miny' => doc.at_xpath('//latLonBoundingBox/miny/text()').to_s,
          'maxx' => doc.at_xpath('//latLonBoundingBox/maxx/text()').to_s,
          'maxy' => doc.at_xpath('//latLonBoundingBox/maxy/text()').to_s,
          'crs' => doc.at_xpath('//latLonBoundingBox/crs/text()').to_s
        },
        "abstract" => doc.at_xpath('//abstract/text()').to_s, 
        "supportedFormats" => doc.xpath('//supportedFormats/string').collect{ |t| t.to_s },
        "keywords" => doc.at_xpath('//keywordList').collect { |kl|
          {
            'keyword' => kl.at_xpath('//keyword/text()').to_s
          }
        },
        "metadataLinks" => doc.xpath('//metadataLinks/metadataLink').collect{ |m|
          {
            'type' => m.at_xpath('//type/text()').to_s,
            'metadataType' => m.at_xpath('//metadataType/text()').to_s,
            'content' => m.at_xpath('//content/text()').to_s
          }
        },
      }.freeze
      ap({ :profile_xml_to_hash => h})
      h  
    end


  end
end 
