# frozen_string_literal: true

DiscourseNpnCritiqueEngagement::Engine.routes.draw do
  get "/critique-engagement/leaderboard" => "leaderboards#show"
  get "/critique-engagement/hall-of-fame" => "leaderboards#hall_of_fame"
  get "/critique-engagement/impact" => "impact#show"
  get "/critique-engagement/editors-picks" => "editors_picks#show"
  post "/critique-engagement/editors-picks/pick" => "editors_picks#pick"
  get "/critique-engagement/outreach" => "editors_picks#outreach"

  scope "/admin/plugins/critique-engagement", constraints: StaffConstraint.new do
    get "/report" => "admin/reports#index"
    get "/health" => "admin/reports#health"
    get "/outreach" => "admin/outreach#index"
    get "/outreach/:user_id/notes" => "admin/outreach#notes"
    post "/outreach/notes" => "admin/outreach#create"
  end
end
