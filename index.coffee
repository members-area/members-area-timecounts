module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/settings/timecounts', 'members-area-timecounts#timecounts#settings'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)
    done()

  modifyNavigationItems: ({addItem}) ->
    addItem 'settings',
      title: 'Timecounts'
      id: 'members-area-timecounts-timecounts-settings'
      href: '/settings/timecounts'
      priority: 71
      permissions: ['admin']
    return

