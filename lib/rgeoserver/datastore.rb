
module RGeoServer
  # A data store is a source of spatial data that is vector based. It can be a file in the case of a Shapefile, a database in the case of PostGIS, or a server in the case of a remote Web Feature Service.
  class DataStore < ResourceInfo

    class DataStoreAlreadyExists < StandardError
      def initialize(name)
        @name = name
      end

      def message
        "The DataStore '#{@name}' already exists and can not be replaced."
      end
    end

    class DataTypeNotExpected < StandardError
      def initialize(data_type)
        @data_type = data_type
      end

      def message
        "The DataStore does not not accept the data type '#{@data_type}'."
      end
    end

    OBJ_ATTRIBUTES = {
      :catalog => 'catalog', 
      :workspace => 'workspace', 
      :connection_parameters => "connection_parameters",
      :name => 'name', 
      :data_type => 'type', 
      :enabled => 'enabled', 
      :description => 'description'
    }  
    OBJ_DEFAULT_ATTRIBUTES = {
      :catalog => nil, 
      :workspace => nil, 
      :connection_parameters => {}, 
      :name => nil, 
      :data_type => 'Shapefile',
      :enabled => 'true', 
      :description=>nil
    }  
    
    define_attribute_methods OBJ_ATTRIBUTES.keys
    update_attribute_accessors OBJ_ATTRIBUTES

    attr_accessor :message

    @@route = "workspaces/%s/datastores"
    @@root = "dataStores"
    @@resource_name = "dataStore"

    def self.root
      @@root
    end

    def self.resource_name
      @@resource_name
    end

    def self.root_xpath
      "//#{root}/#{resource_name}"
    end

    def self.member_xpath
      "//#{resource_name}"
    end

    def route
      @@route % @workspace.name
    end

    def update_route
      "#{route}/#{@name}"
    end

    def message
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.dataStore {
          xml.name @name
          xml.enabled @enabled
          xml.description @description
          xml.type_ @data_type if (data_type_changed? || new?)
          xml.connectionParameters {  # this could be empty
            @connection_parameters.each_pair { |k,v|
              xml.entry(:key => k) {
                xml.text v
              }
            } unless @connection_parameters.nil? || @connection_parameters.empty?
          }
        }
      end
      builder.doc.to_xml
    end

    # @param [RGeoServer::Catalog] catalog
    # @param [RGeoServer::Workspace|String] workspace
    # @param [String] name
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

        @name = options[:name].strip
        @route = route
      end
    end

    def featuretypes
      yield self.class.list FeatureType, @catalog, profile['featureTypes'], {:workspace => @workspace, :data_store => self}, true
    end

    # @param [String] file_path
    # @param [Hash] options { data_type: [:shapefile] }. optional
    def upload_file file_path, options = {}
      raise DataStoreAlreadyExists, @name unless new?

      options = options.dup

      data_type = options.delete(:data_type) || :shapefile
      data_type = data_type.to_sym

      publish = options.delete(:publish) || false

      upload_url_suffix = case data_type
                          when :shapefile then "#{update_route}/file.shp"
                          else
                            raise DataTypeNotExpected, data_type
                          end

      @catalog.client[upload_url_suffix].put File.read(file_path), :content_type => 'application/zip'

      clear
      connection_parameters['url'] = connection_parameters['url'].gsub(/.*data/, '').insert(0, 'file:data') #correct to relative path
      save
      clear

      if publish
        ft = RGeoServer::FeatureType.new @catalog, :workspace => @workspace, :data_store => self, :name => @name
        ft.title = ft.name.capitalize
        ft.abstract = ft.name.capitalize
        ft.enabled = true

        bounds = case data_type
                 when :shapefile
                   shpInfo = ShapefileInfo.new file_path
                   shpInfo.bounds
                 else
                   raise DataTypeNotExpected, data_type
                 end

        ft.native_bounds['minx'], ft.native_bounds['miny'], ft.native_bounds['maxx'], ft.native_bounds['maxy'] =
          bounds.to_a
        ft.projection_policy = :force
        ft.save

        layers = catalog.get_layers workspace: @workspace
        layers.find_all{ |layer| layer.name == ft.name }.each do |layer|
          layer.enabled = true
          layer.save
        end
      end

      self
    end

    def profile_xml_to_hash profile_xml
      doc = profile_xml_to_ng profile_xml
      h = {
        "name" => doc.at_xpath('//name').text.strip,
        "description" => doc.at_xpath('//description/text()').to_s,
        "enabled" => doc.at_xpath('//enabled/text()').to_s,
        'type' => doc.at_xpath('//type/text()').to_s,
        "connection_parameters" => doc.xpath('//connectionParameters/entry').inject({}){ |x, e| x.merge(e['key']=> e.text.to_s) }
      }
      # XXX: assume that we know the workspace for <workspace>...</workspace>
      doc.xpath('//featureTypes/atom:link[@rel="alternate"]/@href', 
                "xmlns:atom"=>"http://www.w3.org/2005/Atom" ).each do |l|
        h["featureTypes"] = begin
                              response = @catalog.do_url l.text
                              # lazy loading: only loads featuretype names
                              Nokogiri::XML(response).xpath('//name/text()').collect{ |a| a.text.strip }
                            rescue RestClient::ResourceNotFound
                              []
                            end.freeze
      end
      h
    end
  end
end
