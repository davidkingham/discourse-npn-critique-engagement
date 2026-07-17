# frozen_string_literal: true

DiscourseNpnCritiqueEngagement::Engine.routes.draw do
  get "/critique-engagement/leaderboard" => "leaderboards#show"
  get "/critique-engagement/hall-of-fame" => "leaderboards#hall_of_fame"
  get "/critique-engagement/impact" => "impact#show"

  # Moderator tools live under /moderate — the dashboard at the root, the
  # work surfaces beneath it.
  get "/moderate" => "moderate#show"
  get "/moderate/editors-picks" => "editors_picks#show"
  post "/moderate/editors-picks/pick" => "editors_picks#pick"
  post "/moderate/editors-picks/unpick" => "editors_picks#unpick"
  get "/moderate/outreach" => "editors_picks#page_shell"
  get "/moderate/report" => "editors_picks#page_shell"

  # The tools briefly shipped under /critique-engagement — keep early
  # bookmarks working.
  get "/critique-engagement/editors-picks", to: redirect("/moderate/editors-picks", status: 301)
  get "/critique-engagement/outreach", to: redirect("/moderate/outreach", status: 301)
  get "/critique-engagement/moderate", to: redirect("/moderate", status: 301)

  scope "/admin/plugins/critique-engagement", constraints: StaffConstraint.new do
    get "/report" => "admin/reports#index"
    get "/health" => "admin/reports#health"
    get "/outreach" => "admin/outreach#index"
    get "/outreach/:user_id/notes" => "admin/outreach#notes"
    post "/outreach/notes" => "admin/outreach#create"
    post "/outreach/claim" => "admin/outreach#claim"
    delete "/outreach/claim" => "admin/outreach#unclaim"
  end
end
