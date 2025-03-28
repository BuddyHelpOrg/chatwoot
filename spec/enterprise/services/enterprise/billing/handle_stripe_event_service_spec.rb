require 'rails_helper'

describe Enterprise::Billing::HandleStripeEventService do
  subject(:stripe_event_service) { described_class }

  let(:event) { double }
  let(:data) { double }
  let(:subscription) { double }
  let!(:account) { create(:account, custom_attributes: { stripe_customer_id: 'cus_123' }) }

  before do
    allow(event).to receive(:data).and_return(data)
    allow(data).to receive(:object).and_return(subscription)
    allow(subscription).to receive(:[]).with('plan')
                                       .and_return({
                                                     'id' => 'test', 'product' => 'plan_id', 'name' => 'plan_name'
                                                   })
    allow(subscription).to receive(:[]).with('quantity').and_return('10')
    allow(subscription).to receive(:[]).with('status').and_return('active')
    allow(subscription).to receive(:[]).with('current_period_end').and_return(1_686_567_520)
    allow(subscription).to receive(:customer).and_return('cus_123')
    create(:installation_config, {
             name: 'CHATWOOT_CLOUD_PLANS',
             value: [
               {
                 'name' => 'Hacker',
                 'product_id' => ['plan_id'],
                 'price_ids' => ['price_1']
               },
               {
                 'name' => 'Startups',
                 'product_id' => ['plan_id_2'],
                 'price_ids' => ['price_2']
               }
             ]
           })
  end

  describe '#perform' do
    context 'when it gets customer.subscription.updated event' do
      it 'updates subscription attributes' do
        allow(event).to receive(:type).and_return('customer.subscription.updated')
        allow(subscription).to receive(:customer).and_return('cus_123')
        stripe_event_service.new.perform(event: event)

        expect(account.reload.custom_attributes).to eq({
                                                         'captain_responses_usage' => 0,
                                                         'stripe_customer_id' => 'cus_123',
                                                         'stripe_price_id' => 'test',
                                                         'stripe_product_id' => 'plan_id',
                                                         'plan_name' => 'Hacker',
                                                         'subscribed_quantity' => '10',
                                                         'subscription_ends_on' => Time.zone.at(1_686_567_520).as_json,
                                                         'subscription_status' => 'active'
                                                       })
      end

      it 'resets captain usage' do
        5.times { account.increment_response_usage }
        expect(account.custom_attributes['captain_responses_usage']).to eq(5)

        allow(event).to receive(:type).and_return('customer.subscription.updated')
        allow(subscription).to receive(:customer).and_return('cus_123')
        stripe_event_service.new.perform(event: event)

        expect(account.reload.custom_attributes['captain_responses_usage']).to eq(0)
      end
    end

    it 'disable features on customer.subscription.updated for default plan' do
      allow(event).to receive(:type).and_return('customer.subscription.updated')
      allow(subscription).to receive(:customer).and_return('cus_123')
      stripe_event_service.new.perform(event: event)
      expect(account.reload.custom_attributes).to eq({
                                                       'captain_responses_usage' => 0,
                                                       'stripe_customer_id' => 'cus_123',
                                                       'stripe_price_id' => 'test',
                                                       'stripe_product_id' => 'plan_id',
                                                       'plan_name' => 'Hacker',
                                                       'subscribed_quantity' => '10',
                                                       'subscription_ends_on' => Time.zone.at(1_686_567_520).as_json,
                                                       'subscription_status' => 'active'
                                                     })
      expect(account).not_to be_feature_enabled('channel_email')
      expect(account).not_to be_feature_enabled('help_center')
    end

    it 'handles customer.subscription.deleted' do
      stripe_customer_service = double
      allow(event).to receive(:type).and_return('customer.subscription.deleted')
      allow(Enterprise::Billing::CreateStripeCustomerService).to receive(:new).and_return(stripe_customer_service)
      allow(stripe_customer_service).to receive(:perform)
      stripe_event_service.new.perform(event: event)
      expect(Enterprise::Billing::CreateStripeCustomerService).to have_received(:new).with(account: account)
    end
  end

  describe '#perform for Startups plan' do
    before do
      allow(event).to receive(:data).and_return(data)
      allow(data).to receive(:object).and_return(subscription)
      allow(subscription).to receive(:[]).with('plan')
                                         .and_return({
                                                       'id' => 'test', 'product' => 'plan_id_2', 'name' => 'plan_name'
                                                     })
      allow(subscription).to receive(:[]).with('quantity').and_return('10')
      allow(subscription).to receive(:customer).and_return('cus_123')
    end

    it 'enable features on customer.subscription.updated' do
      allow(event).to receive(:type).and_return('customer.subscription.updated')
      allow(subscription).to receive(:customer).and_return('cus_123')
      stripe_event_service.new.perform(event: event)
      expect(account.reload.custom_attributes).to eq({
                                                       'captain_responses_usage' => 0,
                                                       'stripe_customer_id' => 'cus_123',
                                                       'stripe_price_id' => 'test',
                                                       'stripe_product_id' => 'plan_id_2',
                                                       'plan_name' => 'Startups',
                                                       'subscribed_quantity' => '10',
                                                       'subscription_ends_on' => Time.zone.at(1_686_567_520).as_json,
                                                       'subscription_status' => 'active'
                                                     })
      expect(account).to be_feature_enabled('channel_email')
      expect(account).to be_feature_enabled('help_center')
    end
  end
end
