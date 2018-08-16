require 'httparty'
require 'sinatra'
require 'logger'
require 'uri'

set :bind, '0.0.0.0'
set :logger, Logger.new(STDOUT)

class JenkinsBuildTriggerRequest
  include HTTParty

  base_uri "#{ENV['JENKINS_URL']}/job/#{ENV['GITHUB_ORGANIZATION']}"
  basic_auth ENV['JENKINS_USER'], ENV['JENKINS_PASSWORD']
  headers 'Content-Type' => 'application/x-www-form-urlencoded'

  def self.perform(repo_name:, branch_name:, pr_number:)
    path = "/job/#{repo_name}/job/#{branch_name}/build"
    payload = {
      parameter: [
        { name: 'REVIEW_APP_CLEANING', value: 'true' },
        { name: 'PR_STATUS', value: 'closed' },
        { name: 'PR_NUMBER', value: pr_number.to_s },
      ]
    }

    post(path, body: "json=#{URI.encode(payload.to_json)}")
  end
end

class WebhookProxyApp
  ALLOWED_WEBHOOK_EVENTS = %w(pull_request)

  def initialize(request)
    @body = request.body
    @webhook_event = request.env['HTTP_X_GITHUB_EVENT']
  end

  def payload
    @payload ||= @body.rewind && JSON.parse(@body.read)
  end

  def repo_name
    @repo_name ||= payload['repository']['name']
  end

  def branch_name
    @branch_name ||= payload['pull_request']['head']['ref']
  end

  def pr_number
    @pr_number ||= payload['number']
  end

  def pr_status
    @pr_status ||= payload['action']
  end

  def allowed_event?
    return true
    ALLOWED_WEBHOOK_EVENTS.include?(@webhook_event)
  end

  def pr_is_closed?
    pr_status == 'closed'
  end

  def trigger_jenkins_build
    JenkinsBuildTriggerRequest.perform(
      repo_name: repo_name,
      branch_name: branch_name,
      pr_number: pr_number,
    )
  end
end

post '/github-payload' do
  @app = WebhookProxyApp.new(request)

  unless @app.allowed_event?
    logger.info('Not interesting, thanks')
    return 200
  end

  payload = @app.payload
  logger.info("Pull request #{@app.pr_number} is #{@app.pr_status}")

  if @app.pr_is_closed?
    resp = @app.trigger_jenkins_build
    logger.info(
      "Triggered Jenkins clean-up build for branch #{@app.branch_name}"
    )

    logger.info("Jenkins response code: #{resp.code}")
    logger.info("Jenkins response message: #{resp.message}")
  end

  return 200
end

