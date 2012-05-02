
module RGeoServer

    class Style < ResourceInfo

      OBJ_ATTRIBUTES = {:catalog => 'catalog', :name => 'name', :sld_version => 'sldVersion', :filename => 'filename', :sld_doc => 'sld_doc' }
      OBJ_DEFAULT_ATTRIBUTES = {:catalog => nil, :name => nil, :sld_version => nil, :filename => '', :sld_doc => nil }

      define_attribute_methods OBJ_ATTRIBUTES.keys
      update_attribute_accessors OBJ_ATTRIBUTES

      @@r = Confstruct::Configuration.new(:route => 'styles', :resource_name => 'style', :sld_namespace => 'http://www.opengis.net/sld')
  
      def self.resource_name
        @@r.resource_name
      end

      def self.create_method 
        :post 
      end

      def self.update_method 
        :put 
      end
 
      def self.root_xpath
        "//#{@@r.route}/#{@@r.resource_name}"
      end

      def self.member_xpath
        "//#{resource_name}"
      end

      def route
        @@r.route  
      end
   
      def create_options
        {
          :headers => {
            :accept => :xml,
            :content_type=> "application/vnd.ogc.sld+xml"
          },
          :format => :xml,
          :name => @name
        }
      end   
      
      def update_options
        {
          :headers => {
            :accept => :xml,
            :content_type=> "application/vnd.ogc.sld+xml"
          },
          :format => :sld
        }
      end
 
      def sld_namespace
        @@r.sld_namespace
      end

      def message
        @sld_doc
      end

      # @param [RGeoServer::Catalog] catalog
      # @param [Hash] options
      def initialize catalog, options
        super({})
        _run_initialize_callbacks do
          @catalog = catalog
          @name = options[:name].strip
        end        
        @route = route
      end
  
      # Obtain all layers that use this style.
      # WARNING: This will be slow and inneficient when the list of all layers is too long.
      def layers &block
        return to_enum(:layers).to_a unless block_given?
        @catalog.get_layers do |l|
          lyrs = [l.profile['default_style']]+l.profile['alternate_styles']
          yield l if lyrs.include? @name
        end 
      end

      def profile_xml_to_hash profile_xml
        doc = profile_xml_to_ng profile_xml
        h = {
          'name' => doc.at_xpath('//name').text.strip, 
          'sld_version' => doc.at_xpath('//sldVersion/version/text()').to_s,
          'filename' => doc.at_xpath('//filename/text()').to_s,
          'sld_doc' => begin
            Nokogiri::XML(@catalog.search({:styles => @name}, options={:format => 'sld'})).to_xml
          rescue RestClient::ResourceNotFound
            nil 
          end
        }.freeze 
        h 
      end
 
    end
end 