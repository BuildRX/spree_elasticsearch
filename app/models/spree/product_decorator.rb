module Spree
  Product.class_eval do
    def facet_properties
      facet_props = {}

      product_properties.each do |prod_prop|
        facet_props[prod_prop.property.id] = prod_prop.value
      end
      facet_props
    end
  end
end