Controller = require 'members-area/app/controller'

module.exports = class Timecounts extends Controller
  @before 'ensureAdmin', only: ['settings']
  @before 'loadRoles', only: ['settings']
  @before 'handleSettings', only: ['settings']

  handleSettings: (done) ->
    @data.roleId ?= @plugin.get('roleId') ? 1
    @data.apiToken ?= @plugin.get('apiToken')

    if @req.method is 'POST' and @req.body.saveSettings is 'true'
      @plugin.set {apiToken: @data.apiToken, roleId: @data.roleId}

    done()

  settings: ->

  loadRoles: (done) ->
    @req.models.Role.find (err, @roles) =>
      done(err)

  ensureAdmin: (done) ->
    return @redirectTo "/login?next=#{encodeURIComponent @req.path}" unless @req.user?
    return done new @req.HTTPError 403, "Permission denied" unless @req.user.can('admin')
    done()
