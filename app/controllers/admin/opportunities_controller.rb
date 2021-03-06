# Fat Free CRM
# Copyright (C) 2008-2009 by Michael Dvorkin
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

class Admin::OpportunitiesController < Admin::ResourceController
  layout 'crm'

  before_filter :load_settings, :except => [ :new, :destroy ]
  before_filter :get_data_for_sidebar, :only => :index
  before_filter :auto_complete, :only => :auto_complete
  after_filter  :update_recently_viewed, :only => :show

  around_filter ScopedAccess::Filter.new(Opportunity, :mine)
  around_filter ScopedAccess::Filter.new(Account, :mine)
  around_filter ScopedAccess::Filter.new(Contact, :mine)
  around_filter ScopedAccess::Filter.new(Campaign, :mine)

  # GET /opportunities
  # GET /opportunities.xml
  #----------------------------------------------------------------------------
  def index
    @opportunities = get_opportunities(:page => params[:page])

    respond_to do |format|
      format.html # index.html.haml
      format.js   # index.js.rjs
      format.xml  { render :xml => @opportunities }
    end
  end

  # GET /opportunities/1
  # GET /opportunities/1.xml                                               HTML
  #----------------------------------------------------------------------------
  def show
    @opportunity = current_user.opportunities.find(params[:id])
    @comment = Comment.new

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @opportunity }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :xml)
  end

  # GET /opportunities/new
  # GET /opportunities/new.xml                                             AJAX
  #----------------------------------------------------------------------------
  def new
    @opportunity = Opportunity.new(:user => current_user, :stage => "prospecting")
    @users       = current_user.sites.first.users.except(current_user)
    @account     = Account.new(:user => current_user)
    @accounts    = current_user.accounts.all(:order => "name")
    if params[:related]
      model, id = params[:related].split("_")
      instance_variable_set("@#{model}", model.classify.constantize.my(current_user).find(id))
    end

    respond_to do |format|
      format.js   # new.js.rjs
      format.xml  { render :xml => @opportunity }
    end

  rescue ActiveRecord::RecordNotFound # Kicks in if related asset was not found.
    respond_to_related_not_found(model, :js) if model
  end

  # GET /opportunities/1/edit                                              AJAX
  #----------------------------------------------------------------------------
  def edit
    @opportunity = current_user.opportunities.find(params[:id])
    @users = current_user.sites.first.users.except(current_user)
    @account  = @opportunity.account || Account.new(:user => current_user)
    @accounts = current_user.accounts.all(:order => "name")
    if params[:previous] =~ /(\d+)\z/
      @previous = current_user.opportunities.find($1)
    end

  rescue ActiveRecord::RecordNotFound
    @previous ||= $1.to_i
    respond_to_not_found(:js) unless @opportunity
  end

  # POST /opportunities
  # POST /opportunities.xml                                                AJAX
  #----------------------------------------------------------------------------
  def create
    @opportunity = Opportunity.new(params[:opportunity])

    respond_to do |format|
      if @opportunity.save_with_account_and_permissions(params)
        if called_from_index_page?
          @opportunities = get_opportunities
          get_data_for_sidebar
        elsif @opportunity.campaign
          @campaign = @opportunity.campaign.reload # Reload the campaign to refresh its summary.
        end
        format.js   # create.js.rjs
        format.xml  { render :xml => @opportunity, :status => :created, :location => @opportunity }
      else
        @users = current_user.sites.first.users.except(current_user)
        @accounts = current_user.accounts.all(:order => "name")
        unless params[:account][:id].blank?
          @account = Account.find(params[:account][:id])
        else
          if request.referer =~ /\/accounts\/(.+)$/
            @account = Account.find($1) # related account
          else
            @account = Account.new(:user => current_user)
          end
        end
        @contact = Contact.find(params[:contact]) unless params[:contact].blank?
        @campaign = Campaign.find(params[:campaign]) unless params[:campaign].blank?
        format.js   # create.js.rjs
        format.xml  { render :xml => @opportunity.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /opportunities/1
  # PUT /opportunities/1.xml                                               AJAX
  #----------------------------------------------------------------------------
  def update
    @opportunity = current_user.opportunities.find(params[:id])

    respond_to do |format|
      if @opportunity.update_with_account_and_permissions(params)
        get_data_for_sidebar if called_from_index_page?
        format.js
        format.xml  { head :ok }
      else
        @users = current_user.sites.first.users.except(current_user)
        @accounts = current_user.accounts.all(:order => "name")
        if @opportunity.account
          @account = Account.find(@opportunity.account.id)
        else
          @account = Account.new(:user => current_user)
        end
        format.js
        format.xml  { render :xml => @opportunity.errors, :status => :unprocessable_entity }
      end
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:js, :xml)
  end

  # DELETE /opportunities/1
  # DELETE /opportunities/1.xml                                   HTML and AJAX
  #----------------------------------------------------------------------------
  def destroy
    @opportunity = current_user.opportunities.find(params[:id])
    @opportunity.destroy if @opportunity

    respond_to do |format|
      format.html { respond_to_destroy(:html) }
      format.js   { respond_to_destroy(:ajax) }
      format.xml  { head :ok }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html, :js, :xml)
  end

  # GET /campaigns/search/query                                           AJAX
  #----------------------------------------------------------------------------
  def search
    @opportunities = get_opportunities(:query => params[:query], :page => 1)

    respond_to do |format|
      format.js   { render :action => :index }
      format.xml  { render :xml => @opportunities.to_xml }
    end
  end

  # POST /opportunities/auto_complete/query                                AJAX
  #----------------------------------------------------------------------------
  # Handled by before_filter :auto_complete, :only => :auto_complete

  # GET /opportunities/options                                             AJAX
  #----------------------------------------------------------------------------
  def options
    unless params[:cancel] == "true"
      @per_page = current_user.pref[:opportunities_per_page] || Opportunity.per_page
      @outline  = current_user.pref[:opportunities_outline]  || Opportunity.outline
      @sort_by  = current_user.pref[:opportunities_sort_by]  || Opportunity.sort_by
      @sort_by  = Opportunity::SORT_BY.invert[@sort_by]
    end
  end

  # POST /opportunities/redraw                                             AJAX
  #----------------------------------------------------------------------------
  def redraw
    current_user.pref[:opportunities_per_page] = params[:per_page] if params[:per_page]
    current_user.pref[:opportunities_outline]  = params[:outline]  if params[:outline]
    current_user.pref[:opportunities_sort_by]  = Opportunity::SORT_BY[params[:sort_by]] if params[:sort_by]
    @opportunities = get_opportunities(:page => 1)
    render :action => :index
  end

  # POST /opportunities/filter                                             AJAX
  #----------------------------------------------------------------------------
  def filter
    session[:filter_by_opportunity_stage] = params[:stage]
    @opportunities = get_opportunities(:page => 1)
    render :action => :index
  end

  private
  #----------------------------------------------------------------------------
  def get_opportunities(options = { :page => nil, :query => nil })
    self.current_page = options[:page] if options[:page]
    self.current_query = options[:query] if options[:query]

    records = {
      :user => current_user,
      :order => current_user.pref[:opportunities_sort_by] || Opportunity.sort_by
    }
    pages = {
      :page => current_page,
      :per_page => current_user.pref[:opportunities_per_page]
    }

    # Call :get_opportunities hook and return its output if any.
    opportunities = hook(:get_opportunities, self, :records => records, :pages => pages)
    return opportunities.last unless opportunities.empty?

    # Default processing if no :get_opportunities hooks are present.
    if session[:filter_by_opportunity_stage]
      filtered = session[:filter_by_opportunity_stage].split(",")
      current_query.blank? ? Opportunity.my(records).only(filtered) : Opportunity.my(records).only(filtered).search(current_query)
    else
      current_query.blank? ? Opportunity.my(records) : Opportunity.my(records).search(current_query)
    end.paginate(pages)
  end

  #----------------------------------------------------------------------------
  def respond_to_destroy(method)
    if method == :ajax
      if called_from_index_page?
        get_data_for_sidebar
        @opportunities = get_opportunities
        if @opportunities.blank?
          @opportunities = get_opportunities(:page => current_page - 1) if current_page > 1
          render :action => :index and return
        end
      else # Called from related asset.
        self.current_page = 1
        @campaign = @opportunity.campaign # Reload related campaign if any.
      end
      # At this point render destroy.js.rjs
    else
      self.current_page = 1
      flash[:notice] = "#{@opportunity.name} has beed deleted."
      redirect_to(opportunities_path)
    end
  end

  #----------------------------------------------------------------------------
  def get_data_for_sidebar
    load_settings
    @opportunity_stage_total = { :all => current_user.opportunities.count, :other => 0 }
    @stage.keys.each do |key|
      @opportunity_stage_total[key] = current_user.opportunities.count(:conditions => [ "stage=?", key.to_s ])
      @opportunity_stage_total[:other] -= @opportunity_stage_total[key]
    end
    @opportunity_stage_total[:other] += @opportunity_stage_total[:all]
  end

  #----------------------------------------------------------------------------
  def load_settings
    @stage = Setting.as_hash(:opportunity_stage)
  end

  protected
    def mine
      {
        :find => { :conditions => ["site_id = ?", current_site.id] },
        :create => { :site_id => current_site.id }
      }
    end

end
