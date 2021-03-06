Url = require 'url'

class Timecounts
  constructor: (@plugin) ->

  httpModule: (url) ->
    if url.match /^http:/
      require('http')
    else
      require('https')

  perform: (method, url, data, callback) ->
    apiToken = @plugin.get('apiToken')
    fullURL = "#{@plugin.endpoint()}#{url}"
    http = @httpModule(fullURL)

    options = Url.parse(fullURL)
    options.method = method
    options.headers =
      Accept: "application/json"
    if token = @plugin.get('apiToken')
      options.headers.Authorization = "Token token=\"#{token}\""
    if data?
      data = JSON.stringify(data) unless typeof data is 'string'
      options.headers["Content-Type"] = "application/json"
      options.headers["Content-Length"] = data.length

    req = http.request options, (res) =>
      responseBody = new Buffer("")
      res.on 'data', (chunk) =>
        responseBody = Buffer.concat [responseBody, chunk]
      res.on 'end', =>
        try
          dataString = responseBody.toString('utf8')
          dataJson = JSON.parse dataString
          payload =
            status: res.statusCode
            headers: res.headers
            data: dataJson
        catch e
          # XXX: beware
          return callback e
        if res.statusCode >= 400
          callback payload
        else
          callback null, payload
    req.on 'error', callback
    if data?
      req.write data
    req.end()

  get: (url, callback) ->
    @perform('get', url, null, callback)

  post: (url, data, callback) ->
    @perform('post', url, data, callback)

  put: (url, data, callback) ->
    @perform('put', url, data, callback)

  delete: (url, callback) ->
    @perform('delete', url, null, callback)

module.exports =
  initialize: (done) ->
    @app.addRoute 'all', '/settings/timecounts', 'members-area-timecounts#timecounts#settings'
    @hook 'navigation_items', @modifyNavigationItems.bind(this)
    @timecounts = new Timecounts(@)
    done()

  endpoint: ->
    (@get('endpoint') ? "https://timecounts-api.herokuapp.com").replace(/\/+$/, "")

  modifyNavigationItems: ({addItem}) ->
    addItem 'settings',
      title: 'Timecounts'
      id: 'members-area-timecounts-timecounts-settings'
      href: '/settings/timecounts'
      priority: 71
      permissions: ['admin']
    return
