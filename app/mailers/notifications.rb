class Notifications < ActionMailer::Base
  default from: "editor@benyehuda.org" # TODO: un-hardcode

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.notifications.proof_fixed.subject
  #
  def proof_fixed(proof, url, m)
    @greeting = t(:hello_anon)
    @proof = proof
    @url = url
    unless m.nil?
      @url = 'https://benyehuda.org'+@url # TODO: un-hardcode
    end
    @m = m
    mail to: proof.from
  end

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.notifications.proof_wontfix.subject
  #
  def proof_wontfix(proof, url, m)
    @greeting = t(:hello_anon)
    @proof = proof
    @url = url
    unless m.nil?
      @url = 'https://benyehuda.org'+@url # TODO: un-hardcode
    end
    @m = m
    mail to: proof.from
  end

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.notifications.recommendation_accepted.subject
p  #
  def recommendation_accepted(rec, url)
    @greeting = t(:hello_anon)
    @rec = rec
    @url = url

    mail to: rec.from
  end

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.notifications.recommendation_published.subject
  #
  def recommendation_published(rec, html_url, blog_url)
    @greeting = t(:hello_anon)
    @published_url = blog_url
    @rec = rec
    @url = html_url
    mail to: rec.from
  end
end
