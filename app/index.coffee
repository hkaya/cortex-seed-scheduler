inject              = require 'honk-di'
{Ajax, XMLHttpAjax} = require 'ajax'
{EditorialView}     = require 'cortex-editorial-view'
{AdView}            = require 'vistar-ad-view-cortex'
adConfig            = require('vistar-ad-view-cortex').config

# Cortex App API.
# See http://api-doc.cortexpowered.com/ for API documentation.
Cortex = window.Cortex

# Main entry point of the application.
init = ->
  # At this point, Cortex player has initialized the DOM.
  #
  # We can render content manually by manipulating the DOM directly:
  #   video = document.createElement('video')
  #   video.src = 'video-url'
  #   document.body.appendChild(video)
  #
  # This approach is not ideal as it will get out of hand easily as the
  # applications become more complex. Mainly, we need a way of:
  #  - Rendering content for a period of time
  #  - Controling the order of content views
  #  - Transitioning from one content view to another
  #  - Prioritizing content views, and
  #  - Handle errors gracefully when one content view fails (applications
  #    should always render something, empty screens are not acceptable).
  # 
  # Cortex provides a default Scheduler (Cortex.view.*) to take care of the
  # above tasks for you. However, you are not required to use our
  # implementation. You can build a custom scheduler that fits your needs and
  # build your applications on top of your scheduler. Cortex scheduler will
  # give you a good starting point: https://github.com/hkaya/cortex-scheduler
  #
  # Note that, we are constantly improving the Cortex Scheduler. If you need
  # some custom behavior, let us know. If it is a feature that other applications
  # will also benefit from, we can make it part of the standard library.
  #
  # Another important concept of Cortex applications is Cortex views. You can
  # think of a Cortex view as a web page within a web site (Cortex application).
  # Views are focused on the presentation and preperation of the content.
  # They don't usually care about the Scheduler or how they will get rendered.
  # A Cortex view is responsible to generate a page to be rendered for a period
  # of time by the scheduler. Views doesn't need to know about each other, their
  # only task is to prepare a page and propose it to the scheduler. Since they
  # are decoupled, you can easily move a view to its own package and reuse it
  # within different applications.
  #
  # In this application we are going to use two pre-built views. The pre-built
  # views are:
  #
  # * Cortex editorial view (https://github.com/hkaya/cortex-editorial-view):
  #   This view will be responsible to prepare editorial images to be displayed
  #   on screen.
  #
  # * Vistar ad view (https://github.com/network-os/adview-cortex):
  #   This view will be responsible to fetch and render ads from Vistar ad
  #   server.
  #
  # You can fork one of these views to build your own view.
  #
  # The purpose of this app is to give you a starting point. In reality, you are
  # not forced to build apps in this way. Although we haven't really tested them,
  # you should be able to use a single-page web app framework like AngularJS or
  # ReactJS to to build applications.

  # vistar-ad-view-cortex uses dependency injection. You might want to consider
  # using DI for other views as well to take advantage of DI.
  # See the documentation for details of initializing an AdView:
  # https://github.com/network-os/adview-cortex
  class Binder extends inject.Binder
    configure: ->
      @bind(Ajax).to XMLHttpAjax
      @bindConstant('navigator').to window.navigator
      @bindConstant('config').to adConfig.config
      @bindConstant('cortex').to Cortex

  injector = new inject.Injector(new Binder)

  # Get an AdView instance. At this point, the AdView is ready to prepare ad
  # views, but we still need to plug in to the scheduler.
  adView = injector.getInstance AdView

  # Cortex apps are configurable. You can modify the paramaters once you upload
  # your app to Cortex dashboard. See the KB for details:
  # http://kb.cortexpowered.com/display/player/Configurable+Applications+And+Cortex+Parameters
  cortexConfig = Cortex?.getConfig()

  # We need to configure the Editorial views. This application will expose two
  # configuration parameters for editorials:
  #   cortex.editorial.duration: Defines for how long we should display an
  #     editorial image view.
  #   cortex.editorial.feeds: A space separated list of RSS feeds for editorial
  #     content. We are going to create a separate EditorialView instance for
  #     each feed to simplify processing. Each EditorialView is responsible to
  #     fetch and parse the RSS feed and submit prepared HTML pages to the
  #     scheduler.
  
  # EditorialView configuration options.
  # See https://github.com/hkaya/cortex-editorial-view
  editorialOpts =
    displayTime:      7500
    assetCacheTTL:    7 * 24 * 60 * 60 * 1000
    feedCacheTTL:     24 * 60 * 60 * 1000
    feedCachePeriod:  30 * 60 * 1000

  editorialDuration = cortexConfig?['cortex.editorial.duration']
  if editorialDuration?
    editorialOpts.displayTime = Number(editorialDuration)

  editorialFeeds = cortexConfig?['cortex.editorial.feeds']
  editorialViews = []
  if not not editorialFeeds
    feeds = editorialFeeds.split(' ')
    for feed in feeds
      feed = feed.trim()
      if not not feed
        console.log """Creating editorial view for feed: #{feed} and \
          duration: #{editorialOpts.displayTime}"""
        editorialViews.push new EditorialView(feed, editorialOpts)

  if editorialViews.length == 0
    console.log "No editorial feeds found."

  adSlotName = adView.constructor.name
  editorialSlotName = editorialViews[0].constructor.name

  # Configure the scheduler
  # Basically we need to create view buckets for each view type (ads and
  # editorial) and define the view order. Once started, the scheduler
  # will check view buckets in defined order and render one page.
  # The Scheduler expects each view to generate pages before they get rendered,
  # instead of generating pages right at the moment they will get displayed. 
  # This approach is important as it will force the views to prepare the
  # page (cache images, generate html) before hand and than propose them to the
  # Scheduler. By preventing I/O and html generation at rendering time,
  # Scheduler guarantees that the pages it has in buckets are always valid - so,
  # no empty screens!

  # The logic below is specific to this particular app.
  # cortex.schedule parameter is a comma separated list of 'a's and 'e's to
  # indicate the view order. For instance, 'a,e,a' means to display an ad,
  # followed by an editorial image and then followed by another ad.
  schedule = cortexConfig?['cortex.schedule']
  hasAds = false
  if not not schedule
    views = schedule.split(',')
    for view in views
      view = view.trim()
      view = view.toLowerCase()
      switch view
        when 'a'
          console.log "Scheduling an ad view."
          hasAds = true
          if editorialViews.length > 0
            # Cortex.view.register() creates a view bucket in Scheduler.
            # In this case, we define editorials to be fallbacks for ads.
            # At any point, when the scheduler tries to render an ad page
            # and there are none available (ad server may be down, internet
            # may be out, etc.), it will try to render an editorial image
            # instead.
            Cortex?.view.register adSlotName, editorialSlotName
          else
            # If there are no editorial views we don't have a fallback for ads.
            Cortex?.view.register adSlotName
        when 'e'
          if editorialViews.length > 0
            console.log "Scheduling an editorial view."
            Cortex?.view.register editorialSlotName
        else
          console.log "Unknown view: #{view}"

  for view in editorialViews
    # Start the editorial views. This will make editorial views to parse their
    # feeds, cache the images and submit an html page to the scheduler
    # right away. Once the Scheduler starts rendering an editorial page,
    # EditorialView's will prepare and submit the next view. This is the expected
    # behavior of all views: Submit one view and while it gets rendered prepare
    # the next one.
    view.run()

  if hasAds
    # Cortex Scheduler supports a third level of fallback, called the default
    # view. Default views are meant to be the safety net so ideally these pages
    # should not involve any I/O (or anything that may result in a rendering
    # problem).
    # 
    # Below we set the default view to track the ad view. This is a convinience
    # method where we set the default view to track recent N submissions to the
    # ad view and rotate them when everything else fails.
    #
    # See https://github.com/hkaya/cortex-scheduler for details.
    Cortex?.view.setDefaultView adSlotName
    # Start the ad view. Similar to the EditorialView's, AdView will immediately
    # submit an ad page and prepare another while this one gets rendered.
    adView.run()
  else
    Cortex?.view.setDefaultView editorialSlotName

  # These are for convenience. You can open up the developer console at any time
  # to inspect the status of your apps. Hit Ctrl+Shift+D to open up the dev
  # console.
  window.__cortex_scheduler = Cortex?.view
  window.__ad_view = adView

  # Finally start the scheduler. This will start the rendering.
  Cortex?.view.start()

module.exports = init()
