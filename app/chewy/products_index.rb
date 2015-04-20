class ProductsIndex < Chewy::Index
  define_type Spree::Product.includes(:taxons, :master, :prices, {:product_properties => :property}) do
    field :status, value: ->(product){ product.availability }
    field :name
    field :description
    field :image_url, type: 'string', value: ->(product){ product.image && product.image.attachment.url(:listing) }
    field :price, type: 'float', value: ->(product){ product.price.to_f }
    field :slug, type: 'string'
    field :facet_properties, type: 'object', value: ->(product){ product.facet_properties }
    field :department, type: 'string', value: ->(product){ product.department }
    field :taxon_lft, type: 'integer', value: ->(product){ product.taxon.lft }
    field :taxon_positions, type: 'integer', value: ->(product){
      positions = {}
      product.taxons.select('spree_taxons.id, spree_products_taxons.position').map{|t| positions[t.id] = t.position }
      positions
    }
    # Locations is disabled out the box but can be added with the following:
    # field :location, type: 'geo_point', value: ->(product){ product.location }
    field :available_on, type: 'integer', value: ->(product){ product.available_on.to_i }
  end
end