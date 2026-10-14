# The AI assistant tab: multi-session chat over the account's own data, with charts, reports and kept snippets.
class AiAssistantController < ApplicationController
  def index
    @providers = AiProvider.enabled.ordered.to_a
  end
end
