module SpreeElasticsearch
  class Searcher
    attr_accessor :properties
    attr_accessor :current_user
    attr_accessor :current_currency

    def initialize params
      @properties = {}
      if params[:taxon]
        @properties[:taxon] = params[:taxon]
      end
      if params[:location]
        @properties[:location] = params[:location]
      end
      prepare params
    end

    def filtered_properties
      @filtered_properties ||= Spree::Property.facet_ids.map { |prop| prop.to_s }
    end

    def facets
      @facets = retrieve_facets
    end

    def base_scope
      scope = ProductsIndex
      if @properties[:taxon]
        taxon_id = @properties[:taxon]
        scope = scope.filter { taxons == taxon_id }
        if @properties[:location]
          scope = scope.filter( geo_distance: {distance: "100miles", location: @properties[:location]} )
        end
      end

      scope.facets(facet_config)
    end

    def retrieve_facets
      facet_conf = {}
      property_ids = Spree::Property.all.pluck(:id)
      property_ids.each do |property_id|
        facet_conf[property_id.to_s] = {terms: {field: property_id.to_s, size: 1000}}
      end
      base_scope.facets(facet_conf).facets
    end

    def products
      @products ||= retrieve_products
    end

    def retrieve_products
      scope = base_scope
      if @properties[:keywords]
        scope = scope.query(query_string: {query: @properties[:keywords], default_operator: 'and'})
      end

      property_filters = {}
      filtered_properties.each do |prop|
        next unless value = @properties[prop].presence
        property_ids = Spree::Property.where(presentation: Spree::Property.find(prop).presentation).pluck(:id).sort.join(',')
        if property_filters[property_ids]
          property_filters[property_ids].push(*value)
        else
          property_filters[property_ids] = value
        end
      end

      property_filters.each do |prop, val|
        val = val.uniq
        property_ids = prop.split(',')
        scope = scope.filter {
          property_ids.map { |k|
            send('facet_properties').send(k.to_s, :or) == val.map(&:to_i)
          }.reduce do |memo, o| memo | o end
        }
      end

      price_range = {gte: @properties[:price_min].try(:to_f), lte: @properties[:price_max].try(:to_f)}.keep_if{|k,v| v.present? }
      if price_range.present?
        scope = scope.filter(range: {price: price_range})
      end

      if @properties[:distance] && @properties[:location]
        scope = scope.filter(geo_distance: {distance: "#{@properties[:distance]}miles", location: @properties[:location]})
      end

      case @properties[:sort]
        when 'price_desc'
          scope = scope.order(price: :desc)
        when 'price_asc'
          scope = scope.order(price: :asc)
        when 'time_desc'
          scope = scope.order(available_on: :desc)
        else
          scope = scope.order("taxon_positions.#{@properties[:taxon]}")
      end

      scope = scope.limit(@properties[:per_page]).offset(@properties[:offset])

      scope.only(:id).load
    end

    def facet_config
      facet_config = {}
      filtered_properties.each do |prop|
        facet_config[prop] = {terms: {field: prop}}
      end

      facet_config
    end

    def prepare params

      filtered_properties.each do |prop|
        @properties[prop] = params[prop].presence
      end

      # Filtering
      [:price_min, :price_max, :keywords, :distance].each do |key|
        if params[key].present?
          @properties[key] = params[key]
        end
      end

      # Pagination
      @properties[:per_page] = Spree::Config[:products_per_page]
      @properties[:page] = 1
      if params[:page] && params[:page].to_i > 0
        @properties[:page] = params[:page].to_i
      end
      @properties[:offset] = @properties[:per_page] * (@properties[:page] - 1)

      # Sorting
      @properties[:sort] = ''
      if params[:sort]
        @properties[:sort] = params[:sort]
      end
    end
  end
end
