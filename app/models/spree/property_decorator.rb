module Spree
  Property.class_eval do
    def self.facet_ids
      self.pluck(:id)
    end
  end
end