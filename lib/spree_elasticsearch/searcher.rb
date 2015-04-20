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

    def filtered_options
      @filtered_options ||= Spree::OptionType.pluck(:id).map { |opt| opt.to_s }
    end

    def facets
      @facets = retrieve_facets
    end

    def base_scope
      time_now = DateTime.now.to_i
      scope = ProductsIndex.filter { available_on < time_now }
      if @properties[:taxon]
        taxon_id = @properties[:taxon]
        scope = scope.filter { taxons == taxon_id }
      end
      if @properties[:location]
        scope = scope.filter( geo_distance: {distance: "100miles", location: @properties[:location]} )
      end

      scope.facets(facet_config)
    end

    def retrieve_facets
      facet_conf = {}
      property_ids = Spree::Property.all.pluck(:id)
      property_ids.each do |property_id|
        facet_conf[property_id.to_s] = {terms: {field: property_id.to_s, size: 1000}}
      end

      option_ids = Spree::OptionType.all.pluck(:id)
      option_ids.each do |option_id|
        facet_conf["o_#{option_id.to_s}"] = {terms: {field: "o_#{option_id.to_s}", size: 1000}}
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

      option_filters = {}
      filtered_options.each do |option|
        next unless value = @properties["o_#{option}"].presence
        option_ids = Spree::OptionType.where(presentation: Spree::OptionType.find(option).presentation).pluck(:id).sort.join(',')
        if option_filters[option_ids]
          option_filters[option_ids].push(*value)
        else
          option_filters[option_ids] = value
        end
      end

      property_filters.each do |prop, val|
        val = val.uniq
        property_ids = prop.split(',')
        scope = scope.filter {
          property_ids.map { |k|
            send('facet_properties').send(k.to_s, :or) == val
          }.reduce do |memo, o| memo | o end
        }
      end

      option_filters.each do |opt, val|
        val = val.uniq
        option_ids = opt.split(',')
        scope = scope.filter {
          option_ids.map { |k|
            send('facet_options').send("o_#{k.to_s}", :or) == val
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
        when 'name_asc'
          scope = scope.order(name: :asc)
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

      filtered_options.each do |prop|
        facet_config["o_#{prop}"] = {terms: {field: "o_#{prop}"}}
      end

      facet_config
    end

    def prepare params

      filtered_properties.each do |prop|
        @properties[prop] = params[prop].presence
      end

      filtered_options.each do |opt|
        @properties["o_#{opt}"] = params["o_#{opt}"].presence
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
