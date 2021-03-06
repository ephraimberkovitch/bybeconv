class AdminController < ApplicationController
  before_action :require_editor
  before_action :require_admin, only: [:missing_languages, :missing_genres, :incongruous_copyright, :missing_copyright, :similar_titles]
  autocomplete :manifestation, :title, display_value: :title_and_authors
  autocomplete :person, :name, full: true

  def index
    if current_user && current_user.editor?
      if current_user.has_bit?('handle_proofs')
        @open_proofs = Proof.where(status: 'new').count.to_s
        @escalated_proofs = Proof.where(status: 'escalated').count.to_s
      end
      @open_recommendations = LegacyRecommendation.where(status: 'new').count.to_s
      @conv_todo = Manifestation.where(conversion_verified: false, status: Manifestation.statuses[:published]).count
      @manifestation_count = Manifestation.published.count
      @conv_percent_done = (@manifestation_count - @conv_todo) / @manifestation_count.to_f * 100
      @page_title = t(:dashboard)
      @search = ManifestationsSearch.new(search: [])
    end
  end

  ##############################################
  ## Reports
  def raw_tocs
    @authors = Person.joins(:toc).where('tocs.status = 0').page(params[:page]).per(15)
    @total = Person.joins(:toc).where('tocs.status = 0').count
    @page_title = t(:raw_tocs)
    Rails.cache.write('report_raw_tocs', @total)
  end

  def messy_tocs
    @authors = []
    Person.has_toc.joins(:toc).includes(:toc).each do |p|
      unless p.toc.structure_okay?
        @authors << p
      end
    end
    Rails.cache.write('report_messy_tocs', @authors.count)
  end

  def missing_languages
    ex = Expression.joins([:realizers, :works]).where(realizers: {role: Realizer.roles[:translator]}, works: {orig_lang: 'he'})
    mans = ex.map{|e| e.manifestations[0]}
    @total = mans.length
    @mans = Kaminari.paginate_array(mans).page(params[:page]).per(50)
    @page_title = t(:missing_language_report)
    Rails.cache.write('report_missing_languages', mans.length)
  end

  def missing_genres
    @mans = Manifestation.joins(:expressions).where(expressions: {genre: nil}).page(params[:page]).per(50)
    @total = Manifestation.joins(:expressions).where(expressions: {genre: nil}).count
    @page_title = t(:missing_genre_report)
    Rails.cache.write('report_missing_genres', @total)
  end

  def missing_images
    @authors = Person.where(profile_image_file_name: nil).order('name asc')
    @page_title = t(:missing_images)
    Rails.cache.write('report_missing_images', @authors.count)
  end

  def missing_copyright
    @authors = Person.where(public_domain: nil)
    @total = Manifestation.joins(:expressions).where(expressions: {copyrighted: nil}).count
    @mans = Manifestation.joins(:expressions).where(expressions: {copyrighted: nil}).page(params[:page]).per(50)
    @page_title = t(:missing_copyright_report)
    Rails.cache.write('report_missing_copyright', @total)
  end

  def similar_titles
    prefixes = {}
    @similarities = {}
    Manifestation.all.each {|m|
      next unless m.list_items.where(listkey: 'similar_title_whitelist') == [] # skip whitelisted works
      prefix = [m.cached_people, m.title[0..(m.title.length > 5 ? 5 : -1)]]
      if prefixes[prefix].nil?
        prefixes[prefix] = [m]
      else
        prefixes[prefix] << m
      end
    }
    prefixes.each_pair{|k, v|
      next if v.length < 2
      @similarities[k] = v.sort_by{|m| m.title}
    }
    Rails.cache.write('report_similar_titles', @similarities.keys.length)
  end

  def mark_similar_as_valid
    m = Manifestation.find(params[:id])
    unless m.nil?
      li = ListItem.new(listkey: 'similar_title_whitelist', item: m)
      li.save!
    end
    head :ok
  end

  def suspicious_translations # find works where the author is also a translator -- this *may* be okay, in the case of self-translation, but probably is a mistake
    @total = Manifestation.joins(expressions: [:realizers, works: [:creations]]).where('realizers.person_id = creations.person_id and realizers.role = 3').count # TODO: unhardcode
    @mans = Manifestation.joins(expressions: [:realizers, works: [:creations]]).where('realizers.person_id = creations.person_id and realizers.role = 3').page(params[:page]) # TODO: unhardcode
    @page_title = t(:suspicious_translations_report)
    Rails.cache.write('report_suspicious_translations', @total)
  end

  def assign_proofs
    @p = Proof.where(status: 'new').order('RAND()').limit(1).first
    @p.status = 'assigned'
    @p.save!
    li = ListItem.new(listkey: 'proofs_by_user', user: current_user, item: @p)
    li.save!
    # check if there are any other proofs on this manifestation, and if so, assign them too, for efficiency
    other_proofs = []
    unless @p.manifestation_id.nil?
      other_proofs = Proof.where(status: 'new', manifestation_id: @p.manifestation_id)
    else
      other_proofs = Proof.where(status: 'new', about: @p.about)
    end
    other_proofs.each do |other|
      other.status = 'assigned'
      other.save
      li = ListItem.new(listkey: 'proofs_by_user', user: current_user, item: other)
      li.save!
    end
    li = ListItem.new(listkey: 'proofs_by_user', user: current_user, item: @p)
    li.save!

    redirect_to url_for(action: :index)
  end

  def assign_conversion_verification
    @m = Manifestation.where(conversion_verified: false, status: Manifestation.statuses[:published]).order('RAND()').first
    if @m.conv_counter.nil?
      @m.conv_counter = 1
    else
      @m.conv_counter += 1
    end
    @m.save!
    li = ListItem.new(listkey: 'convs_by_user', user: current_user, item: @m)
    li.save!

    redirect_to url_for(controller: :manifestation, action: :edit, id: @m.id)
  end

  def conversion_verification
    @manifestations = Manifestation.where(conversion_verified: false).order(:title).page(params[:page])
    @total = Manifestation.where(conversion_verified: false).count
    @page_title = t(:conversion_verification_report)
    Rails.cache.write('report_conversion_verification', @total)
  end

  def my_convs
    @u = User.find(params[:id])
    if @u.nil?
      flash[:error] = t(:no_such_user)
      redirect_to action: :index
    else
      @items = ListItem.where(listkey: 'convs_by_user', user: @u)
    end
    render layout: false
  end

  def periodless
    @authors = Person.has_toc.where(period: nil)
    Rails.cache.write('report_periodless', @authors.length)
  end

  # this is a massive report that takes a long time to run!
  def tocs_missing_links
    @author_keys = []
    @tocs_missing_links = {}
    @tocs_linking_to_missing_items = {}
    Person.has_toc.each do |p|
      @tocs_missing_links[p.id] = {orig: [], xlat: []} if @tocs_missing_links[p.id].nil? # it may already exist because of being translated by an author we've already processed
      toc_items = []
      begin
        toc_items = p.toc.linked_items
      rescue ActiveRecord::RecordNotFound
        @tocs_linking_to_missing_items[p.id] = []
        found_item_ids = []
        p.toc.linked_item_ids.each do |mid|
          if Manifestation.exists?(mid)
            found_item_ids << mid
          else
            @tocs_linking_to_missing_items[p.id] << mid
          end
        end
        toc_items = Manifestation.find(found_item_ids)
      end
      p.original_works.each do |m|
        @tocs_missing_links[p.id][:orig] << m unless toc_items.include?(m)
      end
      p.translations.joins(expressions: :works).includes(expressions: :works).each do |m|
        @tocs_missing_links[p.id][:xlat] << m unless toc_items.include?(m)
        # additionally, make sure they appear in the original author's ToC, if it's a manual one (relevant for translated authors who *also* wrote in Hebrew, e.g. Y. L. Perets)
        m.expressions[0].works[0].authors.each do |au|
          unless au.toc.nil?
            unless au.toc.linked_item_ids.include?(m.id)
              @tocs_missing_links[au.id] = {orig: [], xlat: []} if @tocs_missing_links[au.id].nil?
              @tocs_missing_links[au.id][:orig] << m
            end
          end
        end
      end
      unless @tocs_missing_links[p.id][:orig] == [] && @tocs_missing_links[p.id][:xlat] == []
        @author_keys << p.id
      end
    end
    Rails.cache.write('report_tocs_missing_links', @author_keys.length)
  end

  def translated_from_multiple_languages
    @authors = []
    translatees = Person.joins(creations: :work).includes(:works).where('works.orig_lang <> "he"').distinct
    translatees.each {|t|
      if t.works.pluck(:orig_lang).uniq.count > 1
        works_by_lang = {}
        t.works.each { |w|
          works_by_lang[w.orig_lang] = [] if works_by_lang[w.orig_lang].nil?
          works_by_lang[w.orig_lang] << w.expressions[0].manifestations[0] # TODO: generalize
        }
        @authors << [t, t.works.pluck(:orig_lang).uniq, works_by_lang]
      end
    }
    Rails.cache.write('report_translated_from_multiple_languages', @authors.length)
  end

  def incongruous_copyright
    # Manifestation.joins([expressions: [[realizers: :person],:works]]).where(expressions: {copyrighted:true},people: {public_domain:true})
    @incong = []
    Manifestation.all.each {|m|
      calculated_copyright = m.expressions[0].should_be_copyrighted?
      db_copyright = m.expressions[0].copyrighted
      if calculated_copyright != db_copyright
        @incong << [m, m.title, m.author_string, calculated_copyright, db_copyright]
      end
    }
    Rails.cache.write('report_incongruous_copyright', @incong.length)
  end

  def suspicious_headings
    mm = Manifestation.where('length(cached_heading_lines)>3')
    @suspicious = []
    mm.each do |m|
      suspicious = false
      prev = -10
      m.cached_heading_lines.split('|').each do |l|
        line_no = l.to_i
        if line_no - prev < 5
          lines = m.markdown.split("\n")
          if lines[prev..line_no].join.length < 500 # probably too short for separate chapter/section
            suspicious = true
          end
        end
        prev = line_no
      end
      @suspicious << m if suspicious
    end
    Rails.cache.write('report_suspicious_headings', @suspicious.length)
  end

  #######################################
  ## Static pages management
  def static_pages_list
    @vps = StaticPage.page(params[:page])
  end

  def static_page_new
    @vp = StaticPage.new
    respond_to do |format|
      format.html
      format.json { render json: @vp }
    end
  end

  def static_page_create
    @vp = StaticPage.new(sp_params)
    respond_to do |format|
      if @vp.save
        format.html { redirect_to url_for(action: :static_page_show, id: @vp.id), notice: t(:updated_successfully) }
        format.json { render json: @vp, status: :created, location: @vp }
      else
        format.html { render action: 'static_page_new'}
        format.json { render json: @vp.errors, status: :unprocessable_entity }
      end
    end
  end

  def static_page_show
    @vp = StaticPage.find(params[:id])
    if @vp.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
    @markdown = @vp.prepare_markdown
  end

  def static_page_edit
    @vp = StaticPage.find(params[:id])
  end

  def static_page_update
    @vp = StaticPage.find(params[:id])
    if @vp.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    else
      if @vp.update_attributes(sp_params)
        flash[:notice] = I18n.t(:updated_successfully)
        redirect_to action: :static_page_show, id: @vp.id
      else
        format.html { render action: 'static_page_edit' }
        format.json { render json: @vp.errors, status: :unprocessable_entity }
      end
    end
  end


  #######################################
  ## Volunteer profiles management
  def volunteer_profiles_list
    @vps = VolunteerProfile.page(params[:page])
  end

  def volunteer_profile_new
    @vp = VolunteerProfile.new
    respond_to do |format|
      format.html
      format.json { render json: @vp }
    end
  end

  def volunteer_profile_create
    @vp = VolunteerProfile.new(vp_params)
    respond_to do |format|
      if @vp.save
        format.html { redirect_to url_for(action: :volunteer_profile_show, id: @vp.id), notice: t(:updated_successfully) }
        format.json { render json: @vp, status: :created, location: @vp }
      else
        format.html { render action: 'volunteer_profile_new'}
        format.json { render json: @vp.errors, status: :unprocessable_entity }
      end
    end
  end

  def volunteer_profile_show
    @vp = VolunteerProfile.find(params[:id])
    if @vp.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  def volunteer_profile_edit
    @vp = VolunteerProfile.find(params[:id])
  end

  def volunteer_profile_update
    @vp = VolunteerProfile.find(params[:id])
    if @vp.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    else
      if @vp.update_attributes(vp_params)
        flash[:notice] = I18n.t(:updated_successfully)
        redirect_to action: :volunteer_profile_show, id: @vp.id
      else
        format.html { render action: 'volunteer_profile_edit' }
        format.json { render json: @vp.errors, status: :unprocessable_entity }
      end
    end
  end

  def volunteer_profile_add_feature
    unless params[:fromdate].nil? or params[:todate].nil?
      vp = VolunteerProfile.find(params[:vpid])
      unless vp.nil?
        vpf = VolunteerProfileFeature.new(fromdate: Date.new(params[:fromdate][:year].to_i, params[:fromdate][:month].to_i, params[:fromdate][:day].to_i),
          todate: Date.new(params[:todate][:year].to_i, params[:todate][:month].to_i, params[:todate][:day].to_i))
        vpf.volunteer_profile = vp
        vpf.save!

        flash[:notice] = I18n.t(:created_successfully)
        redirect_to url_for(action: :volunteer_profile_show, id: params[:vpid].to_i)
      else
        flash[:error] = I18n.t(:no_such_item)
        redirect_to url_for(action: :index)
      end
    end
  end

  def volunteer_profile_delete_feature
    vpf = VolunteerProfileFeature.find(params[:id])
    unless vpf.nil?
      vpid = vpf.volunteer_profile_id
      vpf.destroy!
      flash[:notice] = I18n.t(:deleted_successfully)
      redirect_to url_for(action: :volunteer_profile_show, id: vpid)
    else
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  def volunteer_profile_destroy
    @vp = VolunteerProfile.find(params[:id])
    unless @vp.nil?
      @vp.destroy
    end
    flash[:notice] = I18n.t(:deleted_successfully)
    redirect_to action: :volunteer_profile_list
  end

  ########################################################
  ## featured content
  def featured_content_list
    @fcs = FeaturedContent.page(params[:page])
  end

  def featured_content_new
    @fc = FeaturedContent.new
    respond_to do |format|
      format.html
      format.json { render json: @fc }
    end
  end

  def featured_content_create
    @fc = FeaturedContent.new(fc_params)
    @fc.user = current_user
    unless params[:linked_manifestation].empty?
      @fc.manifestation = Manifestation.find(params[:linked_manifestation])
    end
    unless params[:linked_author].empty?
      @fc.person = Person.find(params[:linked_author])
    end

    respond_to do |format|
      if @fc.save
        format.html { redirect_to url_for(action: :featured_content_show, id: @fc.id), notice: t(:updated_successfully) }
        format.json { render json: @fc, status: :created, location: @fc }
      else
        format.html { render action: 'featured_content_new'}
        format.json { render json: @fc.errors, status: :unprocessable_entity }
      end
    end
  end

  def featured_content_show
    @fc = FeaturedContent.find(params[:id])
    if @fc.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  def featured_content_edit
    @fc = FeaturedContent.find(params[:id])
  end

  def featured_content_update
    @fc = FeaturedContent.find(params[:id])
    if @fc.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    else
      unless params[:linked_manifestation].empty?
        @fc.manifestation = Manifestation.find(params[:linked_manifestation])
      end
      unless params[:linked_author].empty?
        @fc.person = Person.find(params[:linked_author])
      end
      @fc.save
      if @fc.update_attributes(fc_params)
        flash[:notice] = I18n.t(:updated_successfully)
        redirect_to action: :featured_content_show, id: @fc.id
      else
        format.html { render action: 'featured_content_edit' }
        format.json { render json: @fc.errors, status: :unprocessable_entity }
      end
    end
  end

  def featured_content_destroy
    @fc = FeaturedContent.find(params[:id])
    unless @fc.nil?
      @fc.destroy
    end
    flash[:notice] = I18n.t(:deleted_successfully)
    redirect_to action: :featured_content_list
  end

  def featured_content_add_feature
    unless params[:fromdate].nil? or params[:todate].nil?
      fc = FeaturedContent.find(params[:fcid])
      unless fc.nil?
        fcf = FeaturedContentFeature.new(fromdate: Date.new(params[:fromdate][:year].to_i, params[:fromdate][:month].to_i, params[:fromdate][:day].to_i),
          todate: Date.new(params[:todate][:year].to_i, params[:todate][:month].to_i, params[:todate][:day].to_i))
        fcf.featured_content = fc
        fcf.save!

        flash[:notice] = I18n.t(:created_successfully)
        redirect_to url_for(action: :featured_content_show, id: fc.id)
      else
        flash[:error] = I18n.t(:no_such_item)
        redirect_to url_for(action: :index)
      end
    end
  end

  def featured_content_delete_feature
    fcf = FeaturedContentFeature.find(params[:id])
    unless fcf.nil?
      fcid = fcf.featured_content_id
      fcf.destroy!
      flash[:notice] = I18n.t(:deleted_successfully)
      redirect_to url_for(action: :featured_content_show, id: fcid)
    else
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  ## sitenotices
  def sitenotice_list
    @sns = Sitenotice.page(params[:page])
  end

  def sitenotice_new
    @sn = Sitenotice.new
    respond_to do |format|
      format.html
      format.json { render json: @sn }
    end
  end

  def sitenotice_create
    @sn = Sitenotice.new(body: sn_params[:body], status: (sn_params[:status] == '1' ? :enabled : :disabled))
    @sn.fromdate = Date.new(params[:fromdate][:year].to_i, params[:fromdate][:month].to_i, params[:fromdate][:day].to_i)
    @sn.todate = Date.new(params[:todate][:year].to_i, params[:todate][:month].to_i, params[:todate][:day].to_i)
    respond_to do |format|
      if @sn.save
        Rails.cache.delete("sitenotices") # clear cached sitenotices
        format.html { redirect_to url_for(action: :sitenotice_show, id: @sn.id), notice: t(:updated_successfully) }
        format.json { render json: @sn, status: :created, location: @sn }
      else
        format.html { render action: 'sitenotice_new'}
        format.json { render json: @sn.errors, status: :unprocessable_entity }
      end
    end
  end

  def sitenotice_show
    @sn = Sitenotice.find(params[:id])
    if @sn.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  def sitenotice_edit
    @sn = Sitenotice.find(params[:id])
  end

  def sitenotice_update
    @sn = Sitenotice.find(params[:id])
    @sn.body = sn_params[:body]
    @sn.status = (sn_params[:status] == '1' ? :enabled : :disabled)
    @sn.fromdate = Date.new(params[:fromdate][:year].to_i, params[:fromdate][:month].to_i, params[:fromdate][:day].to_i)
    @sn.todate = Date.new(params[:todate][:year].to_i, params[:todate][:month].to_i, params[:todate][:day].to_i)
    if @sn.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    else
      if @sn.save
        Rails.cache.delete("sitenotices") # clear cached sitenotices
        flash[:notice] = I18n.t(:updated_successfully)
        redirect_to action: :sitenotice_show, id: @sn.id
      else
        format.html { render action: 'sitenotice_edit' }
        format.json { render json: @sn.errors, status: :unprocessable_entity }
      end
    end
  end

  def sitenotice_destroy
    @sn = Sitenotice.find(params[:id])
    unless @sn.nil?
      @sn.destroy
      Rails.cache.delete("sitenotices") # clear cached sitenotices
    end
    flash[:notice] = I18n.t(:deleted_successfully)
    redirect_to action: :sitenotice_list
  end
  ########################################################
  ## featured author
  def featured_author_list
    @fcs = FeaturedAuthor.page(params[:page])
  end

  def featured_author_new
    @fc = FeaturedAuthor.new
    respond_to do |format|
      format.html
      format.json { render json: @fc }
    end
  end

  def featured_author_create
    @fc = FeaturedAuthor.new(fa_params)
    @fc.person_id = params[:person_id]
    @fc.user = current_user
    respond_to do |format|
      if @fc.save
        format.html { redirect_to url_for(action: :featured_author_show, id: @fc.id), notice: t(:updated_successfully) }
        format.json { render json: @fc, status: :created, location: @fc }
      else
        format.html { render action: 'featured_author_new'}
        format.json { render json: @fc.errors, status: :unprocessable_entity }
      end
    end
  end

  def featured_author_show
    @fc = FeaturedAuthor.find(params[:id])
    if @fc.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  def featured_author_edit
    @fc = FeaturedAuthor.find(params[:id])
  end

  def featured_author_destroy
    @fa = FeaturedAuthor.find(params[:id])
    unless @fa.nil?
      @fa.destroy
    end
    flash[:notice] = I18n.t(:deleted_successfully)
    redirect_to action: :featured_author_list
  end

  def featured_author_update
    @fc = FeaturedAuthor.find(params[:id])
    if @fc.nil?
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    else
      if @fc.update_attributes(fa_params)
        flash[:notice] = I18n.t(:updated_successfully)
        redirect_to action: :featured_author_show, id: @fc.id
      else
        format.html { render action: 'featured_author_edit' }
        format.json { render json: @fc.errors, status: :unprocessable_entity }
      end
    end
  end

  def featured_author_add_feature
    unless params[:fromdate].nil? or params[:todate].nil?
      fc = FeaturedAuthor.find(params[:fcid])
      unless fc.nil?
        fcf = FeaturedAuthorFeature.new(fromdate: Date.new(params[:fromdate][:year].to_i, params[:fromdate][:month].to_i, params[:fromdate][:day].to_i),
          todate: Date.new(params[:todate][:year].to_i, params[:todate][:month].to_i, params[:todate][:day].to_i))
        fcf.featured_author = fc
        fcf.save!

        flash[:notice] = I18n.t(:created_successfully)
        redirect_to url_for(action: :featured_author_show, id: fc.id)
      else
        flash[:error] = I18n.t(:no_such_item)
        redirect_to url_for(action: :index)
      end
    end
  end

  def featured_author_delete_feature
    fcf = FeaturedAuthorFeature.find(params[:id])
    unless fcf.nil?
      fcid = fcf.featured_author_id
      fcf.destroy!
      flash[:notice] = I18n.t(:deleted_successfully)
      redirect_to url_for(action: :featured_author_show, id: fcid)
    else
      flash[:error] = I18n.t(:no_such_item)
      redirect_to url_for(action: :index)
    end
  end

  private

  def vp_params
    params[:volunteer_profile].permit(:name, :bio, :about, :profile_image)
  end
  def fa_params
    params[:featured_author].permit(:title, :body)
  end
  def fc_params
    params[:featured_content].permit(:title, :body, :external_link)
  end
  def sp_params
    params[:static_page].permit(:tag, :title, :body, :status, :mode, :ltr)
  end
  def sn_params
    params[:sitenotice].permit(:body, :status)
  end
end
