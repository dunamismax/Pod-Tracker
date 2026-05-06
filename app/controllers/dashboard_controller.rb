class DashboardController < ApplicationController
  def show
    @commander_meta = Meta::PerformanceSummary.for_user(Current.session.user).commander_meta
  end
end
