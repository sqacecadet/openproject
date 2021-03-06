#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2015 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

OpenProject::Application.routes.draw do
  root to: 'homescreen#index', as: 'home'
  rails_relative_url_root = OpenProject::Configuration['rails_relative_url_root'] || ''

  # Redirect deprecated issue links to new work packages uris
  get '/issues(/)'    => redirect("#{rails_relative_url_root}/work_packages")
  # The URI.escape doesn't escape / unless you ask it to.
  # see https://github.com/rails/rails/issues/5688
  get '/issues/*rest' => redirect { |params, _req| "#{rails_relative_url_root}/work_packages/#{URI.escape(params[:rest])}" }

  # Redirect wp short url for work packages to full URL
  get '/wp(/)'    => redirect("#{rails_relative_url_root}/work_packages")
  get '/wp/*rest' => redirect { |params, _req| "#{rails_relative_url_root}/work_packages/#{URI.escape(params[:rest])}" }

  scope controller: 'account' do
    get '/account/force_password_change', action: 'force_password_change'
    post '/account/change_password', action: 'change_password'
    match '/account/lost_password', action: 'lost_password', via: [:get, :post]
    match '/account/register', action: 'register', via: [:get, :post, :patch]

    # omniauth routes
    match '/auth/:provider/callback', action: 'omniauth_login',
                                      as: 'omniauth_login',
                                      via: [:get, :post]
    get '/auth/failure', action: 'omniauth_failure'

    match '/login', action: 'login',  as: 'signin', via: [:get, :post]
    get '/logout', action: 'logout', as: 'signout'
  end

  namespace :api do
    namespace :v2 do
      resources :authentication
      resources :users, only: [:index]
      resources :planning_element_journals
      resources :statuses
      resources :colors, controller: 'planning_element_type_colors'
      resources :planning_element_types
      resources :planning_elements
      resources :project_types
      resources :reported_project_statuses
      resources :statuses, only: [:index, :show]
      resources :timelines
      resources :planning_element_priorities, only: [:index]

      resources :projects do
        resources :planning_elements
        resources :planning_element_types
        resources :reportings do
          get :available_projects, on: :collection
        end
        resources :project_associations do
          get :available_projects, on: :collection
        end
        resources :statuses, only: [:index, :show]
        resources :versions, only: [:index]
        resources :users, only: [:index]

        member do
          get :planning_element_custom_fields
        end
        resources :workflows, only: [:index]

        collection do
          get :level_list
        end
      end

      resources :custom_fields

      namespace :pagination, as: 'paginate' do
        [:users,
         :principals,
         :statuses,
         :types,
         :project_types,
         :reported_project_statuses,
         :projects].each do |model|
          resources model, only: [:index]
        end
      end
    end

    namespace :experimental do
      resources :work_packages, only: [:index]
      resources :queries, only: [:create, :update, :destroy] do
        get :available_columns, on: :collection
        get :custom_field_filters, on: :collection
        get :grouped, on: :collection
      end

      resources :projects, only: [:show, :index] do
        resources :work_packages, only: [:index] do
          get :column_sums, on: :collection
        end
        resources :queries, only: [:create, :update, :destroy] do
          get :available_columns, on: :collection
          get :custom_field_filters, on: :collection
          get :grouped, on: :collection
        end
        resources :versions, only: [:index]
        get :sub_projects
        resources :users, only: [:index]
      end

      resources :versions, only: [:index]
      resources :groups, only: [:index]
      resources :roles, only: [:index]
      resources :users, only: [:index]
    end
  end

  # Because of https://github.com/intridea/grape/pull/853/files this has to be
  # placed behind handling the deprecated v1 because otherwise, a 405 is
  # returned for all routes for which the v3 has also resources. Grape does
  # remove the prefix (v3) before checking whether the method is supported. I
  # don't understand why that should make sense.
  mount API::Root => '/'

  get '/roles/workflow/:id/:role_id/:type_id' => 'roles#workflow'
  get '/help/:ctrl/:page' => 'help#index'

  resources :types do
    post 'move/:id', action: 'move', on: :collection
  end

  resources :statuses, except: :show do
    collection do
      post 'update_work_package_done_ratio'
    end
  end
  resources :custom_fields, except: :show
  get '(projects/:project_id)/search' => 'search#index', as: 'search'

  # only providing routes for journals when there are multiple subclasses of journals
  # all subclasses will look for the journals routes
  resources :journals, only: :index do
    get 'diff/:field', action: :diff, on: :member, as: 'diff'
  end

  # REVIEW: review those wiki routes
  scope 'projects/:project_id/wiki/:id' do
    resource :wiki_menu_item, only: [:edit, :update]
  end

  scope 'projects/:project_id/query/:query_id' do
    resources :query_menu_items, except: [:show]
  end

  # generic route for adding/removing watchers.
  # Models declared as acts_as_watchable will be automatically added to
  # OpenProject::Acts::Watchable::Routes.watched
  scope ':object_type/:object_id', constraints: OpenProject::Acts::Watchable::Routes do
    match '/watch' => 'watchers#watch', via: :post
    match '/unwatch' => 'watchers#unwatch', via: :delete
  end

  resources :projects, except: [:edit] do
    member do
      # this route let's you access the project specific settings (by tab)
      #
      #   settings_project_path(@project)
      #     => "/projects/1/settings"
      #
      #   settings_project_path(@project, tab: 'members')
      #     => "/projects/1/settings/members"
      #
      get 'settings(/:tab)', action: 'settings', as: :settings

      get 'identifier', action: 'identifier'
      patch 'identifier', action: 'update_identifier'

      match 'copy_project_from_(:coming_from)' => 'copy_projects#copy_project', via: :get, as: :copy_from,
            constraints: { coming_from: /(admin|settings)/ }
      match 'copy_from_(:coming_from)' => 'copy_projects#copy', via: :post, as: :copy,
            constraints: { coming_from: /(admin|settings)/ }
      put :modules
      put :custom_fields
      put :archive
      put :unarchive
      patch :types

      get 'column_sums', controller: 'work_packages'

      # Destroy uses a get request to prompt the user before the actual DELETE request
      get :destroy_info, as: 'confirm_destroy'
    end

    resource :enumerations, controller: 'project_enumerations', only: [:update, :destroy]

    resources :versions, only: [:new, :create] do
      collection do
        put :close_completed
      end
    end

    # this is only another name for versions#index
    # For nice "road in the url for the index action
    # this could probably be rewritten with a resource as: 'roadmap'
    match '/roadmap' => 'versions#index', via: :get

    resources :news, only: [:index, :new, :create]

    namespace :time_entries do
      resource :report, controller: 'reports', only: [:show]
    end
    resources :time_entries, controller: 'timelog'

    # Match everything to be the ID of the wiki page except the part that
    # is reserved for the format. This assumes that we have only two formats:
    # .txt and .html
    resources :wiki,
              constraints: { id: /([^\/]+(?=\.txt|\.html)|[^\/]+)/ },
              except: [:index, :create] do
      collection do
        post '/new' => 'wiki#create', as: 'create'
        get :export
        get :date_index
        post :preview
        get '/index' => 'wiki#index'
      end

      member do
        get '/new' => 'wiki#new_child', as: 'new_child'
        get '/diff/:version/vs/:version_from' => 'wiki#diff', as: 'wiki_diff_compare'
        get '/diff(/:version)' => 'wiki#diff', as: 'wiki_diff'
        get '/annotate/:version' => 'wiki#annotate', as: 'wiki_annotate'
        get '/toc' => 'wiki#index'
        match :rename, via: [:get, :patch]
        get :parent_page, action: 'edit_parent_page'
        patch :parent_page, action: 'update_parent_page'
        get :history
        post :protect
        post :add_attachment
        get :list_attachments
        get :select_main_menu_item, to: 'wiki_menu_items#select_main_menu_item'
        post :replace_main_menu_item, to: 'wiki_menu_items#replace_main_menu_item'
        post :preview
      end
    end
    # as routes for index and show are swapped
    # it is necessary to define the show action later
    # than any other route as it otherwise would
    # work as a catchall for everything under /wiki
    get 'wiki' => 'wiki#show'

    namespace :work_packages do
      resources :calendar, controller: 'calendars', only: [:index]
    end

    resources :work_packages, only: [] do
      collection do
        get '/report/:detail' => 'work_packages/reports#report_details'
        get '/report' => 'work_packages/reports#report'
      end

      # states managed by client-side routing on work_package#index
      get '(/*state)' => 'work_packages#index', on: :collection, as: ''
      get '/create_new' => 'work_packages#index', on: :collection, as: 'new_split'
      get '/new' => 'work_packages#index', on: :collection, as: 'new', state: 'new'
    end

    resources :activity, :activities, only: :index, controller: 'activities'

    resources :boards do
      member do
        get :confirm_destroy
        get :move
        post :move
      end
    end

    resources :categories, except: [:index, :show], shallow: true

    resources :members, only: [:index, :create, :update, :destroy], shallow: true do
      match :autocomplete_for_member, on: :collection, via: [:get, :post]
    end

    resource :repository, controller: 'repositories', except: [:new] do
      get :edit # needed as show is configured manually with a wildcard

      # Destroy uses a get request to prompt the user before the actual DELETE request
      get :destroy_info
      get :committers
      post :committers
      get :graph
      get :revisions

      get '/statistics', action: :stats, as: 'stats'

      get '(/revisions/:rev)/diff.:format', action: :diff
      get '(/revisions/:rev)/diff(/*path)', action: :diff,
                                            format: false

      get '(/revisions/:rev)/:format/*path', action: :entry,
                                             format: /raw/,
                                             rev: /[a-z0-9\.\-_]+/

      %w{diff annotate changes entry browse}.each do |action|
        get "(/revisions/:rev)/#{action}(/*path)", format: false,
                                                   action: action,
                                                   rev: /[a-z0-9\.\-_]+/
      end

      get '/revision(/:rev)', rev: /[a-z0-9\.\-_]+/,
                              action: :revision,
                              as: 'show_revision'

      get '(/revisions/:rev)(/*path)', action: :show,
                                       format: false,
                                       rev: /[a-z0-9\.\-_]+/
    end
  end

  get '/admin' => 'admin#index'

  # TODO: evaluate whether this can be turned into a namespace
  scope 'admin' do
    match '/projects' => 'admin#projects', via: :get, as: :admin_projects

    resource :announcements, only: [:edit, :update]
    resources :enumerations

    resources :groups do
      member do
        get :autocomplete_for_user
        # this should be put into it's own resource
        match '/members' => 'groups#add_users', via: :post, as: 'members_of'
        match '/members/:user_id' => 'groups#remove_user', via: :delete, as: 'member_of'
        # this should be put into it's own resource
        match '/memberships/:membership_id' => 'groups#edit_membership', via: :put, as: 'membership_of'
        match '/memberships/:membership_id' => 'groups#destroy_membership', via: :delete
        match '/memberships' => 'groups#create_memberships', via: :post, as: 'memberships_of'
      end
    end

    resources :roles, only: [:index, :new, :create, :edit, :update, :destroy] do
      collection do
        put '/' => 'roles#bulk_update'
        get :report
      end
    end

    resources :auth_sources, :ldap_auth_sources do
      member do
        get :test_connection
      end
    end
  end

  # We should fix this crappy routing (split up and rename controller methods)
  get '/settings' => 'settings#index'
  scope 'settings', controller: 'settings' do
    match 'edit', action: 'edit', via: [:get, :post]
    match 'plugin/:id', action: 'plugin', via: [:get, :post]
  end

  # We should fix this crappy routing (split up and rename controller methods)
  get '/workflows' => 'workflows#index'
  scope 'workflows', controller: 'workflows' do
    match 'edit', action: 'edit', via: [:get, :post]
    match 'copy', action: 'copy', via: [:get, :post]
  end

  namespace :work_packages do
    match 'auto_complete' => 'auto_completes#index', via: [:get, :post]
    resources :calendar, controller: 'calendars', only: [:index]
    resource :bulk, controller: 'bulk', only: [:edit, :update, :destroy]
    # FIXME: this is kind of evil!! We need to remove this soonest and
    # cover the functionality. Route is being used in work-package-service.js:331
    get '/bulk' => 'bulk#destroy'
  end

  resources :work_packages, only: [:index] do
    get :column_data, on: :collection # TODO move to API

    # move bulk of wps
    get 'move/new' => 'work_packages/moves#new', on: :collection, as: 'new_move'
    post 'move' => 'work_packages/moves#create', on: :collection, as: 'move'
    # move individual wp
    resource :move, controller: 'work_packages/moves', only: [:new, :create]

    # this duplicate mapping is required for the timelog_helper
    namespace :time_entries do
      resource :report, controller: 'reports'
    end
    resources :time_entries, controller: 'timelog'

    # states managed by client-side routing on work_package#index
    get 'details/*state' => 'work_packages#index', on: :collection, as: :details

    # states managed by client-side (angular) routing on work_package#show
    get '/' => 'work_packages#index', on: :collection, as: 'index'
    get '/create_new' => 'work_packages#index', on: :collection, as: 'new_split'
    get '/new' => 'work_packages#index', on: :collection, as: 'new', state: 'new'
    get '(/*state)' => 'work_packages#show', on: :member, as: ''
    get '/edit' => 'work_packages#show', on: :member, as: 'edit'
  end

  resources :versions, only: [:show, :edit, :update, :destroy] do
    member do
      get :status_by
    end
  end

  namespace :time_entries do
    resource :report, controller: 'reports',
                      only: [:show]
  end

  resources :time_entries, controller: 'timelog'

  resources :activity, :activities, only: :index, controller: 'activities'

  resources :users do
    member do
      match '/edit/:tab' => 'users#edit', via: :get, as: 'tab_edit'
      match '/memberships/:membership_id/destroy' => 'users#destroy_membership', via: :post
      match '/memberships/:membership_id' => 'users#edit_membership', via: :post
      match '/memberships' => 'users#edit_membership', via: :post
      post :change_status
      post :edit_membership
      post :destroy_membership
      post :resend_invitation
      get :deletion_info
    end
  end

  resources :boards, only: [] do
    resources :topics, controller: 'messages', except: [:index], shallow: true do
      member do
        get :quote
        post :reply, as: 'reply_to'
        post :preview
      end

      post :preview, on: :collection
    end
  end

  resources :news, only: [:index, :destroy, :update, :edit, :show] do
    resources :comments, controller: 'news/comments', only: [:create, :destroy], shallow: true

    post :preview, on: :member
    post :preview, on: :collection
  end

  resources :attachments, only: [:destroy], format: false do
    member do
      scope via: :get, constraints: { id: /\d+/, filename: /[^\/]*/ } do
        match '(/:filename)' => 'attachments#download', as: 'download'
      end
    end
  end

  # redirect for backwards compatibility
  scope constraints: { id: /\d+/, filename: /[^\/]*/ } do
    get '/attachments/download/:id/:filename' => redirect("#{rails_relative_url_root}/attachments/%{id}/download/%{filename}"), format: false
    get '/attachments/download/:id' => redirect("#{rails_relative_url_root}/attachments/%{id}/download"), format: false
  end

  scope controller: 'sys' do
    match '/sys/repo_auth', action: 'repo_auth', via: [:get, :post]
    match '/sys/projects.:format', action: 'projects', via: :get
    match '/sys/projects/:id/repository/update_storage', action: 'update_required_storage', via: :get
  end

  # alternate routes for the current user
  scope 'my' do
    match '/deletion_info' => 'users#deletion_info', via: :get, as: 'delete_my_account_info'
  end

  scope controller: 'my' do
    post '/my/add_block', action: 'add_block'
    post '/my/remove_block', action: 'remove_block'
    post '/my/order_blocks', action: 'order_blocks'
    get '/my/page_layout', action: 'page_layout'
    get '/my/password', action: 'password'
    post '/my/change_password', action: 'change_password'
    get '/my/page', action: 'page'
    match '/my/account', action: 'account', via: [:get, :patch]
    match '/my/settings', action: 'settings', via: [:get, :patch]
    match '/my/mail_notifications', action: 'mail_notifications', via: [:get, :patch]
    post '/my/reset_rss_key', action: 'reset_rss_key'
    post '/my/generate_rss_key', action: 'generate_rss_key'
    post '/my/reset_api_key', action: 'reset_api_key'
    post '/my/generate_api_key', action: 'generate_api_key'
    get '/my/access_token', action: 'access_token'
  end

  get 'authentication' => 'authentication#index'

  resources :colors, controller: 'planning_element_type_colors' do
    member do
      get :confirm_destroy
      get :move
      post :move
    end
  end

  resources :project_types, controller: 'project_types' do
    member do
      get :confirm_destroy
      get :move
      post :move
    end

    resources :projects, only: [:index, :show], controller: 'projects'
    resources :reported_project_statuses,          controller: 'reported_project_statuses'
  end

  resources :projects, only: [:index, :show], controller: 'projects' do
    resources :project_associations,   controller: 'project_associations' do
      get :confirm_destroy, on: :member
      get :available_projects, on: :collection
    end

    resources :reportings,             controller: 'reportings' do
      get :confirm_destroy, on: :member
    end

    resources :timelines,              controller: 'timelines'
  end

  resources :reported_project_statuses, controller: 'reported_project_statuses'

  # This route should probably be removed, but it's used at least by one cuke and we don't
  # want to break it.
  # This route intentionally occurs after the admin/roles/new route, so that one takes
  # precedence when creating routes (possibly via helpers).
  get 'roles/new' => 'roles#new', as: 'deprecated_roles_new'

  # Install the default route as the lowest priority.
  get '/:controller(/:action(/:id))'
  get '/robots' => 'homescreen#robots', defaults: { format: :txt }

  root to: 'account#login'

  # Development route for styleguide
  if Rails.env.development?
    get '/styleguide' => redirect('/assets/styleguide.html')
  end
end
