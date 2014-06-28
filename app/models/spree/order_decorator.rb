Spree::Order.class_eval do

	has_one :tax_cloud_transaction

	self.state_machine.after_transition :to => :payment, :do => :lookup_tax_cloud, :if => :tax_cloud_eligible?

	self.state_machine.after_transition :to => :complete, :do => :capture_tax_cloud, :if => :tax_cloud_eligible?

	def tax_cloud_eligible?
		ship_address.try(:state_id?)
	end

	def lookup_tax_cloud
		if tax_cloud_transaction.nil?
			create_tax_cloud_transaction
		end
		update_with_taxcloudlookup
	end

	def tax_cloud_adjustment(tax)
		unless ( old_adj = adjustments.where("order_id = ? and  source_type = ?, self.id, tax_cloud_transaction)" )).blank? 
			old_adj.destroy
		else
			adjustments.create do |adjustment|
				adjustment.source = tax_cloud_transaction
				adjustment.label = 'Tax'
				adjustment.mandatory = true
				adjustment.eligible = true
				adjustment.amount = tax
				adjustment.order_id = self.id
			end
		end
	end

	def promotions_total
		adjustments.eligible.promotion.map(&:amount).sum.abs
	end

	def capture_tax_cloud
		return unless tax_cloud_transaction
		tax_cloud_transaction.capture
	end

	def update_with_taxcloudlookup 
		update_without_taxcloud_lookup 
		unless tax_cloud_transaction.nil?
			transaction = Spree::TaxCloudTransaction.transaction_from_order(self)
			response = transaction.lookup
			unless response.blank?
				response_cart_items = response.cart_items
				index = -1
				total_tax = 0.0 
				self.line_items.each do |line_item|
					tax = round_to_two_places( response_cart_items[index += 1].tax_amount ) 
					line_item.additional_tax_total = tax
					total_tax += tax
					binding.pry
				end
				tax_cloud_adjustment(total_tax)
			else
				raise ::SpreeTaxCloud::Error, 'TaxCloud response unsuccessful!'
			end
		end
	end

	alias_method :update_without_taxcloud_lookup, :update! 
	alias_method :update!, :update_with_taxcloudlookup 

	def round_to_two_places(amount)
		BigDecimal.new(amount.to_s).round(2, BigDecimal::ROUND_HALF_UP)
	end
end
