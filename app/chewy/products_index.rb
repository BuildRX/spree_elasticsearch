class ProductsIndex < Chewy::Index
  define_type Spree::Product.includes(:taxons, :master, {:product_properties => :property}) do
    field :name
    field :description
    field :image_url, type: 'string', value: ->(product){ product.image && product.image.attachment.url(:listing) }
    field :price, type: 'float', value: ->(product){ product.master.price.to_f }
    field :slug, type: 'string'
    field :facet_properties, type: 'object', value: ->(product){ product.facet_properties }
    field :taxons, value: ->(product){
      taxons = []
      product.taxons.map{|t| taxons.push(*t.self_and_ancestors.map(&:id))}
      taxons.uniq
    }
    field :taxon_positions, type: 'object', value: ->(product){
      positions = {}
      product.taxons.select('spree_taxons.id, spree_products_taxons.position').map{|t| positions[t.id] = t.position }
      positions
    }
    # Locations is disabled out the box but can be added with the following:
    # field :location, type: 'geo_point', value: ->(product){ product.location }
    field :available_on, type: 'integer', value: ->(product){ product.available_on.to_i }
  end
end