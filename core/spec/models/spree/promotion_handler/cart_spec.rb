# frozen_string_literal: true

require 'rails_helper'

module Spree
  module PromotionHandler
    RSpec.describe Cart, type: :model do
      let(:line_item) { create(:line_item) }
      let(:order) { line_item.order }
      let(:promotion) { create(:promotion, apply_automatically: true) }
      let(:calculator) { Calculator::FlatPercentItemTotal.new(preferred_flat_percent: 10) }

      subject { Cart.new(order, line_item) }

      shared_context "creates the adjustment" do
        it "creates the adjustment" do
          expect {
            subject.activate
          }.to change { adjustable.adjustments.count }.by(1)
        end
      end

      shared_context "creates an order promotion" do
        it "connects the promotion to the order" do
          expect {
            subject.activate
          }.to change { order.promotions.reload.to_a }.from([]).to([promotion])
        end
      end

      context "activates in LineItem level" do
        let!(:action) { Promotion::Actions::CreateItemAdjustments.create(promotion: promotion, calculator: calculator) }
        let(:adjustable) { line_item }

        context "promotion with no rules" do
          include_context "creates the adjustment"
          include_context "creates an order promotion"

          context "for a non-sale promotion" do
            let(:promotion) { create(:promotion, apply_automatically: false) }

            it "doesn't connect the promotion to the order" do
              expect {
                subject.activate
              }.to change { order.promotions.count }.by(0)
            end

            it "doesn't create an adjustment" do
              expect {
                subject.activate
              }.to change { adjustable.adjustments.count }.by(0)
            end
          end
        end

        context "promotion includes item involved" do
          let!(:rule) { Promotion::Rules::Product.create(products: [line_item.product], promotion: promotion) }

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end

        context "promotion does not activate for other items" do
          let(:other_line_item) { create(:line_item) }
          let!(:rule) { Promotion::Rules::Product.create(products: [line_item.product], promotion: promotion) }
          let!(:other_rule) { Promotion::Rules::Product.create(products: [other_line_item.product], promotion: promotion) }

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end

        context "promotion activates for store" do
          let!(:rule) { Promotion::Rules::Store.create(stores: [order.store], promotion: promotion) }

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end

        context "promotion does not activate for other store" do
          let(:other_store) { create(:store) }
          let(:other_promotion) { create(:promotion, apply_automatically: true) }
          let!(:other_rule) { Promotion::Rules::Store.create(stores: [other_store], promotion: other_promotion) }
          let!(:rule) { Promotion::Rules::Store.create(stores: [order.store], promotion: promotion) }

          include_context "creates the adjustment"
          include_context "creates an order promotion"

          it "doesn't connect the promotion to the order" do
            expect {
              subject.activate
            }.to change { order.promotions.count }.by(1)
          end

          it "doesn't create an adjustment" do
            expect {
              subject.activate
            }.to change { adjustable.adjustments.count }.by(1)
          end
        end

        context "promotion activates for user" do
          let!(:rule) { Promotion::Rules::User.create(users: [order.user], promotion: promotion) }

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end

        context "promotion does not activate for other user" do
          let(:user) { create(:user) }
          let!(:rule) { Promotion::Rules::User.create(users: [user], promotion: promotion) }

          it "doesn't connect the promotion to the order" do
            expect {
              subject.activate
            }.to change { order.promotions.count }.by(0)
          end

          it "doesn't create an adjustment" do
            expect {
              subject.activate
            }.to change { adjustable.adjustments.count }.by(0)
          end
        end

        context "promotion has item total rule" do
          let(:shirt) { create(:product) }
          let!(:rule) { Promotion::Rules::ItemTotal.create(preferred_operator: 'gt', preferred_amount: 50, promotion: promotion) }

          before do
            # Makes the order eligible for this promotion
            order.item_total = 100
            order.save
          end

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end
      end

      context "activates in Order level" do
        let!(:action) { Promotion::Actions::CreateAdjustment.create(promotion: promotion, calculator: calculator) }
        let(:adjustable) { order }

        context "promotion with no rules" do
          before do
            # Gives the calculator something to discount
            order.item_total = 10
            order.save
          end

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end

        context "promotion has item total rule" do
          let(:shirt) { create(:product) }
          let!(:rule) { Promotion::Rules::ItemTotal.create(preferred_operator: 'gt', preferred_amount: 50, promotion: promotion) }

          before do
            # Makes the order eligible for this promotion
            order.item_total = 100
            order.save
          end

          include_context "creates the adjustment"
          include_context "creates an order promotion"
        end
      end

      context "activates promotions associated with the order" do
        let(:promotion) { create :promotion, :with_order_adjustment, code: 'promo' }
        let(:promotion_code) { promotion.codes.first }
        let(:adjustable) { order }

        before do
          Spree::OrderPromotion.create!(promotion: promotion, order: order, promotion_code: promotion_code)
          order.recalculate
        end

        include_context "creates the adjustment"

        it "records the promotion code in the adjustment" do
          subject.activate
          expect(adjustable.adjustments.map(&:promotion_code)).to eq [promotion_code]
        end

        it "checks if the promotion code is eligible" do
          expect_any_instance_of(Spree::Promotion).to receive(:eligible?).at_least(2).times.with(anything, promotion_code: promotion_code).and_return(false)
          subject.activate
        end
      end
    end
  end
end
