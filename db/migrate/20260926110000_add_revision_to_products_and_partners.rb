class AddRevisionToProductsAndPartners < ActiveRecord::Migration[8.1]
  # A counter every successful edit increments, so a PATCH can say which
  # version it was based on and lose gracefully to a newer one (ADR 0015). A
  # constant default is a metadata-only change on Postgres 11 and later.
  def change
    add_column :catalog_products, :revision, :integer, null: false, default: 0
    add_column :catalog_partners, :revision, :integer, null: false, default: 0
  end
end
