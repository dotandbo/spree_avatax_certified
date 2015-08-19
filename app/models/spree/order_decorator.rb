require 'logger'

Spree::Order.class_eval do

  has_one :avalara_transaction, dependent: :destroy
  self.state_machine.before_transition :to => :payment,
                                      :do => :avalara_capture,
                                      :if => :avalara_eligible

  self.state_machine.before_transition :to => :complete,
                                      :do => :avalara_capture_finalize,
                                      :if => :avalara_eligible

 self.state_machine.before_transition :to => :canceled,
                                      :do => :cancel_status,
                                      :if => :avalara_eligible

  def avalara_eligible
    Spree::Config.avatax_iseligible
  end

  def avalara_lookup
    logger.debug 'avalara lookup'
    create_avalara_transaction
    :lookup_avatax
  end

  def cancel_status
    return nil unless avalara_transaction.present?
    self.avalara_transaction.check_status(self)
  end

  def avalara_capture
    logger.debug 'avalara capture'

    begin
      create_avalara_transaction
      self.all_adjustments.tax.destroy_all
      self.line_items.reload

      @rtn_tax = self.avalara_transaction.commit_avatax(line_items, self, self.number.to_s, Date.today.strftime("%F"), "SalesInvoice")

      logger.info 'tax amount'
      logger.debug @rtn_tax
      
      unless @rtn_tax == "0"
        @rtn_tax["TaxLines"].each do |tax_line|

          if !tax_line["LineNo"].include? "-"
            line_item = Spree::LineItem.find(tax_line["LineNo"])
            line_item.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = "Tax"
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"]
              adjustment.order = self
              adjustment.state = "closed"
            end
          elsif tax_line["LineNo"].include? "-FR"
            shipment = Spree::Shipment.find(tax_line["LineNo"].split("-").first)
            shipment.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = 'Shipping Tax'
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"].to_f
              adjustment.order = self
              adjustment.state = "closed"
            end
          elsif tax_line["LineNo"].include? "-DSFR"
            delivery_surcharge = Spree::Adjustment.find(tax_line["LineNo"].split("-").first)
            line_item = delivery_surcharge.adjustable
            line_item.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = "Delivery Surcharge Tax (#{line_item.sku})"
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"]
              adjustment.order = self
              adjustment.state = "closed"
            end
          elsif tax_line["LineNo"].include? "-WGFR"
            white_glove_adjustment = Spree::Adjustment.find(tax_line["LineNo"].split("-").first)
            line_item = white_glove_adjustment.adjustable
            line_item.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = "White Glove Tax (#{line_item.sku})"
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"]
              adjustment.order = self
              adjustment.state = "closed"
            end
          end
        end

        self.reload.update!
        all_adjustments.avalara_tax
      end
    rescue => e
      logger.debug e
      logger.debug 'error in a avalara capture'
    end
  end

  def avalara_migrate_finalize
    create_avalara_transaction
    self.avalara_transaction.commit_avatax_final_migration(line_items, self, self.number.to_s, completed_at.strftime("%F"), "SalesInvoice")
  end

  def avalara_capture_finalize
    logger.debug 'avalara capture finalize'

    begin
      create_avalara_transaction
      self.all_adjustments.tax.destroy_all
      self.line_items.reload
      @rtn_tax = self.avalara_transaction.commit_avatax_final(line_items, self, self.number.to_s, Date.today.strftime("%F"), "SalesInvoice")

      logger.info 'tax amount'
      logger.debug @rtn_tax

      unless @rtn_tax == "0"
        @rtn_tax["TaxLines"].each do |tax_line|
          if !tax_line["LineNo"].include? "-"
            line_item = Spree::LineItem.find(tax_line["LineNo"])
            line_item.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = "Tax"
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"]
              adjustment.order = self
              adjustment.state = "closed"
            end
          elsif tax_line["LineNo"].include? "-FR"
            shipment = Spree::Shipment.find(tax_line["LineNo"].split("-").first)
            shipment.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = 'Shipping Tax'
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"].to_f
              adjustment.order = self
              adjustment.state = "closed"
            end
          elsif tax_line["LineNo"].include? "-DSFR"
            delivery_surcharge = Spree::Adjustment.find(tax_line["LineNo"].split("-").first)
            line_item = delivery_surcharge.adjustable
            line_item.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = "Delivery Surcharge Tax (#{line_item.sku})"
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"]
              adjustment.order = self
              adjustment.state = "closed"
            end
          elsif tax_line["LineNo"].include? "-WGFR"
            white_glove_adjustment = Spree::Adjustment.find(tax_line["LineNo"].split("-").first)
            line_item = white_glove_adjustment.adjustable
            line_item.adjustments.create do |adjustment|
              adjustment.source = avalara_transaction
              adjustment.label = "White Glove Tax (#{line_item.sku})"
              adjustment.mandatory = true
              adjustment.eligible = true
              adjustment.amount = tax_line["TaxCalculated"]
              adjustment.order = self
              adjustment.state = "closed"
            end
          end
        end

        self.reload.update!
        all_adjustments.avalara_tax
      end
    rescue => e
      logger.debug e
      logger.debug 'error in a avalara capture finalize'
    end
  end

  def display_avalara_tax_total
    avatax_tax = BigDecimal.new("0")
    self.all_adjustments.avalara_tax.each do |tax|
      avatax_tax += tax.amount
    end
    Spree::Money.new(avatax_tax, { currency: currency })
  end

  private
  def logger
    @logger ||= AvataxHelper::AvataxLog.new("avalara_order", "order class", 'start order processing')
  end
end
