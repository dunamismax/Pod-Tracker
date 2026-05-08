class GameNightMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @game_night = invitation.game_night
    @host = @game_night.user
    @response_url = invitation_response_url(token: invitation.token)

    subject = "#{@host.attribution_name} invited you to #{@game_night.name}"
    mail subject: subject, to: invitation.email_address
  end
end
