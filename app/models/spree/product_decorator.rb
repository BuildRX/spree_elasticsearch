module Spree
  Product.class_eval do
    update_index('products') { self }

    def facet_properties
      facet_props = {}

      product_properties.each do |prod_prop|
        facet_props[prod_prop.property.id] = prod_prop.value
      end

      facet_props
    end

    def facet_options
      facet_opts = {}

      variants.map(&:option_values).map{ |ov|
        if ov.first
          if facet_opts["o_#{ov.first.option_type_id}"].nil?
            facet_opts["o_#{ov.first.option_type_id}"] = []
          end
          facet_opts["o_#{ov.first.option_type_id}"].push(ov.first.presentation)
        end
      }

      facet_opts
    end
  end
end