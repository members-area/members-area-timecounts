Controller = require 'members-area/app/controller'

module.exports = class Timecounts extends Controller
  @before 'ensureAdmin', only: ['settings']
  @before 'loadRoles', only: ['settings']
  @before 'handleSettings', only: ['settings']
  @before 'doLogin', only: ['settings']
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

  doLogin: (done) ->
    return done() unless @req.body.login
    if @req.body.login is 'login'
      # Attempt to login
      data =
        email: @data.email
        password: @data.password
      @plugin.timecounts.post "/users/sign_in", data, (err, response) =>
        if err
          if err.status is 401
            @loginError = "Incorrect username or password"
          else
            @loginError = "Something went wrong"
          return done()
        @loginStep2 = true
        @data.apiToken = response.data.token
        @organizations = {}
        @organizations[org.slug] = org.name for org in response.data.user.admin_organizations
        return done()
    else
      # Step 2
      @plugin.set {apiToken: @data.apiToken, organization: @data.organization}
      return done()

  doSync: (done) ->
    return done() unless @req.body.sync
    @plugin.async.series
      checkExistingTimecountsGroups: (done) =>
        rolesByTimecountsGroupId = {}
        rolesByTimecountsGroupId[role.meta.timecountsId] = role for role in @roles when role.meta?.timecountsId?
        groupIds = Object.keys(rolesByTimecountsGroupId)
        return done() if groupIds.length is 0
        # Check these still exist on timecounts
        @plugin.timecounts.get "/organizations/#{@plugin.get('organization')}/groups?id_in=#{groupIds.join(",")}", (err, response) =>
          return done(new Error("Failed to fetch groups from timecounts.")) if err
          timecountsGroups = response.data
          timecountsGroupsById = {}
          timecountsGroupsById[group.id] = group for group in timecountsGroups
          @plugin.async.eachSeries groupIds, (groupId, done) =>
            if !timecountsGroupsById[groupId]
              # Timecounts can't find this group, it must have been deleted!
              role = rolesByTimecountsGroupId[groupId]
              role.setMeta timecountsId: undefined
              delete rolesByTimecountsGroupId[groupId]
              role.save done
            else
              done()
          , done

      createTimecountsGroups: (done) =>
        groupFromRole = (role) ->
          name: role.name
        create = (role, done) =>
          return done() if role.meta?.timecountsId
          groupData = groupFromRole(role)
          @plugin.timecounts.post "/organizations/#{@plugin.get('organization')}/groups", groupData, (err, response) =>
            next = (err, response) =>
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

      loadUsers: (done) =>
        @req.models.User.find (err, @users) =>
          done(err)

      createUsers: (done) =>
        allUsers = @users[..]
        batches = []
        while allUsers.length > 0
          batches.push allUsers.splice(0, 25)

        processBatch = (users, done) =>
          @plugin.async.series
            checkExistingTimecountsUsers: (done) =>
              usersByTimecountsPersonId = {}
              usersByTimecountsPersonId[user.meta.timecountsId] = user for user in users when user.meta?.timecountsId?
              personIds = Object.keys(usersByTimecountsPersonId)
              return done() if personIds.length is 0
              # Check these people still exist on tiemcounts
              @plugin.timecounts.get "/organizations/#{@plugin.get('organization')}/people?id_in=#{personIds.join(",")}", (err, response) =>
                return done(new Error("Failed to fetch people from timecounts.")) if err
                timecountsPeople = response.data
                timecountsPeopleById = {}
                timecountsPeopleById[person.id] = person for person in timecountsPeople
                @plugin.async.eachSeries personIds, (personId, done) =>
                  if !timecountsPeople[personId]
                    # Timecounts can't find this person, must have been deleted
                    user = usersByTimecountsPersonId[personId]
                    user.setMeta timecountsId: undefined
                    delete usersByTimecountsPersonId[personId]
                    user.save done
                  else
                    done()
                , done

            createTimecountsUsers: (done) =>
              personFromUser = (user) ->
                email: user.email.toLowerCase()
                name: user.fullname
              create = (user, done) =>
                return done() if user.meta?.timecountsId
                personData = personFromUser(user)
                @plugin.timecounts.post "/organizations/#{@plugin.get('organization')}/people", personData, (err, response) =>
                  next = (err, response) =>
                    return done(new Error("Failed to create person in timecounts.")) if err
                    person = response.data
                    if Array.isArray(person)
                      person = person[0]
                    user.setMeta timecountsId: person.id
                    user.save -> done() # ignore errors
                  if err and err.status is 422
                    @plugin.timecounts.get "/organizations/#{@plugin.get('organization')}/people?email=#{encodeURIComponent personData.email}", next
                  else
                    next(err, response)
              @plugin.async.mapSeries users, create, done
          , done
        @plugin.async.mapSeries batches, processBatch, done

    , (err) =>
      return done err if err
