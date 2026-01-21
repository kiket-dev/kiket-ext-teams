# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TeamsNotificationExtension do
  subject(:extension) { described_class.new }

  let(:context) { build_context }
  let(:access_token) { 'test-access-token-123' }

  let(:oauth_stub) do
    stub_request(:post, 'https://login.microsoftonline.com/test-tenant-id/oauth2/v2.0/token')
      .to_return(
        status: 200,
        body: { access_token: access_token }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '#handle_notify' do
    context 'with channel notifications' do
      let(:payload) do
        {
          'channel_type' => 'channel',
          'team_id' => 'team-123',
          'channel_id' => 'channel-456',
          'message' => 'Hello Teams!'
        }
      end

      let(:graph_stub) do
        stub_request(:post, 'https://graph.microsoft.com/v1.0/teams/team-123/channels/channel-456/messages')
          .with(
            headers: {
              'Authorization' => "Bearer #{access_token}",
              'Content-Type' => 'application/json'
            }
          )
          .to_return(
            status: 201,
            body: { id: 'msg-789' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'delivers channel notifications' do
        oauth_stub
        graph_stub

        result = extension.send(:handle_notify, payload, context)

        expect(result[:success]).to be true
        expect(result[:message_id]).to eq('msg-789')
        expect(result[:delivered_at]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end
    end

    context 'with chat notifications' do
      let(:payload) do
        {
          'channel_type' => 'chat',
          'chat_id' => 'chat-123',
          'message' => 'Hello Chat!'
        }
      end

      let(:graph_stub) do
        stub_request(:post, 'https://graph.microsoft.com/v1.0/chats/chat-123/messages')
          .with(
            headers: {
              'Authorization' => "Bearer #{access_token}",
              'Content-Type' => 'application/json'
            }
          )
          .to_return(
            status: 201,
            body: { id: 'msg-456' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'delivers chat notifications' do
        oauth_stub
        graph_stub

        result = extension.send(:handle_notify, payload, context)

        expect(result[:success]).to be true
        expect(result[:message_id]).to eq('msg-456')
      end
    end

    context 'with validation errors' do
      it 'rejects missing message' do
        result = extension.send(:handle_notify, {
                                  'channel_type' => 'channel',
                                  'team_id' => 'team',
                                  'channel_id' => 'channel'
                                }, context)

        expect(result[:success]).to be false
        expect(result[:error]).to include('message is required')
      end

      it 'rejects missing channel_type' do
        result = extension.send(:handle_notify, {
                                  'message' => 'test'
                                }, context)

        expect(result[:success]).to be false
        expect(result[:error]).to include('channel_type is required')
      end

      it 'rejects missing team_id for channel notifications' do
        result = extension.send(:handle_notify, {
                                  'channel_type' => 'channel',
                                  'channel_id' => 'channel',
                                  'message' => 'test'
                                }, context)

        expect(result[:success]).to be false
        expect(result[:error]).to include('team_id is required')
      end

      it 'rejects missing chat_id for chat notifications' do
        result = extension.send(:handle_notify, {
                                  'channel_type' => 'chat',
                                  'message' => 'test'
                                }, context)

        expect(result[:success]).to be false
        expect(result[:error]).to include('chat_id is required')
      end
    end

    context 'with API errors' do
      let(:payload) do
        {
          'channel_type' => 'channel',
          'team_id' => 'team-123',
          'channel_id' => 'channel-456',
          'message' => 'Hello Teams!'
        }
      end

      it 'handles unauthorized errors' do
        oauth_stub
        stub_request(:post, 'https://graph.microsoft.com/v1.0/teams/team-123/channels/channel-456/messages')
          .to_return(status: 401, body: { error: { message: 'Unauthorized' } }.to_json)

        result = extension.send(:handle_notify, payload, context)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Teams API error')
      end

      it 'handles rate limiting' do
        oauth_stub
        stub_request(:post, 'https://graph.microsoft.com/v1.0/teams/team-123/channels/channel-456/messages')
          .to_return(
            status: 429,
            headers: { 'Retry-After' => '60' },
            body: { error: { message: 'Rate limit exceeded' } }.to_json
          )

        result = extension.send(:handle_notify, payload, context)

        expect(result[:success]).to be false
        expect(result[:retry_after]).to eq(60)
      end
    end
  end

  describe '#handle_validate' do
    context 'with valid channel' do
      let(:payload) do
        {
          'channel_type' => 'channel',
          'team_id' => 'team-123',
          'channel_id' => 'channel-456'
        }
      end

      let(:graph_stub) do
        stub_request(:get, 'https://graph.microsoft.com/v1.0/teams/team-123/channels/channel-456')
          .with(headers: { 'Authorization' => "Bearer #{access_token}" })
          .to_return(
            status: 200,
            body: { id: 'channel-456', displayName: 'General' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'validates channel successfully' do
        oauth_stub
        graph_stub

        result = extension.send(:handle_validate, payload, context)

        expect(result[:valid]).to be true
        expect(result[:message]).to include('valid')
      end
    end

    context 'with invalid channel' do
      let(:payload) do
        {
          'channel_type' => 'channel',
          'team_id' => 'team-123',
          'channel_id' => 'invalid-channel'
        }
      end

      let(:graph_stub) do
        stub_request(:get, 'https://graph.microsoft.com/v1.0/teams/team-123/channels/invalid-channel')
          .to_return(status: 404, body: { error: { message: 'Not found' } }.to_json)
      end

      it 'returns invalid for nonexistent channel' do
        oauth_stub
        graph_stub

        result = extension.send(:handle_validate, payload, context)

        expect(result[:valid]).to be false
      end
    end
  end

  describe 'message formatting' do
    it 'converts markdown to HTML' do
      markdown = '**bold** and *italic* text'
      html = extension.send(:markdown_to_html, markdown)

      expect(html).to include('<strong>bold</strong>')
      expect(html).to include('<em>italic</em>')
    end

    it 'escapes HTML in plain text' do
      text = "<script>alert('xss')</script>"
      formatted = extension.send(:format_message, text, 'text')

      expect(formatted).not_to include('<script>')
      expect(formatted).to include('&lt;script&gt;')
    end
  end
end
