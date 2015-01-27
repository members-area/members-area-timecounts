Controller = require 'members-area/app/controller'

module.exports = class Timecounts extends Controller
  @before 'ensureAdmin', only: ['settings']
  @before 'loadRoles', only: ['settings']
  @before 'handleSettings', only: ['settings']
  @before 'doSync', only: ['settings']

  settings: ->

  handleSettings: (done) ->
    @data.roleId ?= @plugin.get('roleId') ? 1
    @data.apiToken ?= @plugin.get('apiToken')
    @data.organization ?= @plugin.get('organization')

    if @req.method is 'POST' and @req.body.saveSettings is 'true'
      @plugin.set {apiToken: @data.apiToken, roleId: @data.roleId, organization: @data.organization}

    done()

  loadRoles: (done) ->
    @req.models.Role.find (err, @roles) =>
      done(err)

  ensureAdmin: (done) ->
    return @redirectTo "/login?next=#{encodeURIComponent @req.path}" unless @req.user?
    return done new @req.HTTPError 403, "Permission denied" unless @req.user.can('admin')
    done()

  doSync: (done) ->
    return done() unless @req.body.sync
    @plugin.async.parallel
      checkExistingTimecountsGroups: (done) =>
        knownIds = {}
        knownIds[role.meta.timecountsId] = role for role in @roles when role.meta?.timecountsId?
        groupIds = Object.keys(knownIds)
        return done() if groupIds.length is 0
        # Fetch from Timecounts
        @plugin.timecounts.get "/organizations/#{@plugin.get('organization')}/groups?id_in=#{groupIds.join(",")}", (err, response) =>
          timecountsGroups = response.data
          return done(new Error("Failed to fetch groups from timecounts.")) if err
          timecountsGroupsById = {}
          timecountsGroupsById[group.id] = group for group in timecountsGroups
          for groupId, role of knownIds
            role.setMeta timecountsId: undefined
            role.save()
            delete knownIds[groupId] unless timecountsGroupsById[groupId]
          @rolesByTimecountsGroupId = knownIds
          done()

      createTimecountsGroups: (done) =>
        groupFromRole = (role) ->
          name: role.name
        create = (role, done) =>
          return done() if role.meta?.timecountsId
          groupData = groupFromRole(role)
          @plugin.timecounts.post "/organizations/#{@plugin.get('organization')}/groups", groupData, (err, response) =>
            next = (err, response) ->
              return done(new Error("Failed to create group in timecounts.")) if err
              group = response.data
              if Array.isArray(group)
                group = group[0]
              role.setMeta timecountsId: group.id
              role.save done
            if err and err.status is 422
              @plugin.timecounts.get "/organizations/#{@plugin.get('organization')}/groups?name=#{encodeURIComponent groupData.name}", next
            else
              next(err, response)
        @plugin.async.mapSeries @roles, create, done

    , (err) =>
      return done err if err
      return done()
