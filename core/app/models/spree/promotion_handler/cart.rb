# frozen_string_literal: true

module Spree
  module PromotionHandler
    # Decides which promotion should be activated given the current order context
    #
    # By activated it doesn't necessarily mean that the order will have a
    # discount for every activated promotion. It means that the discount will be
    # created and might eventually become eligible. The intention here is to
    # reduce overhead. e.g. a promotion that requires item A to be eligible
    # shouldn't be eligible unless item A is added to the order.
    #
    # It can be used as a wrapper for custom handlers as well. Different
    # applications might have completely different requirements to make
    # the promotions system accurate and performant. Here they can plug custom
    # handler to activate promos as they wish once an item is added to cart
    class Cart
      attr_reader :line_item, :order
      attr_accessor :error, :success

      def initialize(order, line_item = nil)
        @order, @line_item = order, line_item
      end

      def activate
        promotions.each do |promotion|
          if (line_item && promotion.eligible?(line_item, promotion_code: promotion_code(promotion))) || promotion.eligible?(order, promotion_code: promotion_code(promotion))
            promotion.activate(line_item: line_item, order: order, promotion_code: promotion_code(promotion))
          end
        end
      end

      private

      def promotions
        connected_order_promotions | sale_promotions
      end

      def connected_order_promotions
        Spree::Promotion.active.includes(:promotion_rules).
          joins(:order_promotions).
          where(spree_orders_promotions: { order_id: order.id }).readonly(false).to_a
      end

      def promotion_code(promotion)
        order_promotion = Spree::OrderPromotion.where(order: order, promotion: promotion).first
        order_promotion.present? ? order_promotion.promotion_code : nil
      end

      def sale_promotions
        scope = Spree::Promotion.where(apply_automatically: true).active.includes(:promotion_rules).distinct

        Rails.application.config.spree.promotions.rules.each do |rule_class|
          next unless rule_class.respond_to? :excluded_promotions_for_order

          scope = scope.where.not(id: rule_class.excluded_promotions_for_order(order).select(:id))
        end

        # Filter promotions that are not eligible for current_user.
        scope = scope.select do |promotion|
          promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::User'").none? ||
            promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::User'")
              .flat_map(&:user_ids).include?(order.user_id)
        end

        # Filter promotions that are not eligible for the selected products in the order.
        scope = scope.select do |promotion|
          promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::Product'").none? ||
            order.product_ids.flat_map { |p_id| promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::Product'").flat_map(&:product_ids).include?(p_id) }.include?(true)
        end

        # Filter promotions that are not eligible for the order's store.
        scope = scope.select do |promotion|
          promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::Store'").none? ||
            promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::Store'").flat_map(&:store_ids)
              .include?(order.store_id)
        end

        scope = scope.select do |promotion|
          promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::Taxon'").none? ||
            order.products.flat_map(&:taxon_ids).uniq.map { |taxon_id|
              promotion.rules.where("spree_promotion_rules.type = 'Spree::Promotion::Rules::Taxon'").flat_map(&:taxon_ids).include?(taxon_id)
            }.include?(true)
        end

        scope
      end
    end
  end
end
